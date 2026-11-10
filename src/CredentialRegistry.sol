// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/// @title CredentialRegistry
/// @notice Educational prototype of the CredentiaChain core use case: approved issuers
///         (universities, employers) register ONLY salted SHA-256 hashes of documents;
///         anyone can verify a hash. No personal data and no funds are ever stored here.
/// @dev Educational project for the course Introduction to Finance.
///      Not a real product, service or investment offer. Do not use with real funds.
///      Roles: DEFAULT_ADMIN_ROLE (consortium multisig in production) manages issuers and can pause;
///      ISSUER_ROLE can register and revoke ITS OWN documents; verification is public (read-only).
contract CredentialRegistry is AccessControl, Pausable {
    using MerkleProof for bytes32[];

    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");

    enum Status {
        NotFound, // hash was never registered
        Valid, // registered, not revoked, not expired, issuer in good standing
        Revoked, // withdrawn by the issuer
        Expired, // past its expiry date
        IssuerSuspended // issuer was suspended by the admin
    }

    struct Credential {
        address issuer; // who registered the hash (0 = not registered)
        uint64 issuedAt;
        uint64 expiresAt; // 0 = never expires
        bool revoked;
        bytes32 docType; // e.g. keccak256("DIPLOMA"), keccak256("EMPLOYMENT_CERT")
    }

    struct Batch {
        address issuer;
        uint64 issuedAt;
        uint32 size;
        bool revoked;
    }

    mapping(bytes32 hash => Credential) private _credentials;
    mapping(bytes32 root => Batch) private _batches;
    mapping(address issuer => string name) public issuerName; // public organisation name only

    event IssuerRegistered(address indexed issuer, string name);
    event IssuerSuspended(address indexed issuer);
    event DocumentIssued(bytes32 indexed hash, address indexed issuer, bytes32 docType, uint64 expiresAt);
    event BatchIssued(bytes32 indexed root, address indexed issuer, uint32 size);
    event DocumentRevoked(bytes32 indexed hash, address indexed issuer);
    event BatchRevoked(bytes32 indexed root, address indexed issuer);

    error AlreadyRegistered(bytes32 hash);
    error NotFoundHash(bytes32 hash);
    error NotOriginalIssuer(address caller, address issuer);
    error AlreadyRevoked(bytes32 hash);
    error InvalidArgument();

    constructor(address admin) {
        if (admin == address(0)) revert InvalidArgument();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // ------------------------------------------------------------------ admin

    /// @notice Approve an organisation as issuer (consortium decision).
    function registerIssuer(address issuer, string calldata name) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (issuer == address(0) || bytes(name).length == 0) revert InvalidArgument();
        issuerName[issuer] = name;
        _grantRole(ISSUER_ROLE, issuer);
        emit IssuerRegistered(issuer, name);
    }

    /// @notice Suspend an issuer (e.g. stolen key). Its documents no longer verify as Valid.
    function suspendIssuer(address issuer) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(ISSUER_ROLE, issuer);
        emit IssuerSuspended(issuer);
    }

    /// @notice Emergency stop for new issuance and revocation. Verification keeps working.
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // ----------------------------------------------------------------- issuer

    /// @notice Register the salted hash of one document.
    function issueDocument(bytes32 hash, bytes32 docType, uint64 expiresAt)
        external
        onlyRole(ISSUER_ROLE)
        whenNotPaused
    {
        if (hash == bytes32(0)) revert InvalidArgument();
        if (_credentials[hash].issuer != address(0)) revert AlreadyRegistered(hash);
        _credentials[hash] = Credential(msg.sender, uint64(block.timestamp), expiresAt, false, docType);
        emit DocumentIssued(hash, msg.sender, docType, expiresAt);
    }

    /// @notice Register a whole graduation in one transaction: only the Merkle root is stored.
    function issueBatch(bytes32 root, uint32 size) external onlyRole(ISSUER_ROLE) whenNotPaused {
        if (root == bytes32(0) || size == 0) revert InvalidArgument();
        if (_batches[root].issuer != address(0)) revert AlreadyRegistered(root);
        _batches[root] = Batch(msg.sender, uint64(block.timestamp), size, false);
        emit BatchIssued(root, msg.sender, size);
    }

    /// @notice Withdraw a document. Only the original issuer can do it.
    function revokeDocument(bytes32 hash) external whenNotPaused {
        Credential storage c = _credentials[hash];
        if (c.issuer == address(0)) revert NotFoundHash(hash);
        if (c.issuer != msg.sender) revert NotOriginalIssuer(msg.sender, c.issuer);
        if (c.revoked) revert AlreadyRevoked(hash);
        c.revoked = true;
        emit DocumentRevoked(hash, msg.sender);
    }

    function revokeBatch(bytes32 root) external whenNotPaused {
        Batch storage b = _batches[root];
        if (b.issuer == address(0)) revert NotFoundHash(root);
        if (b.issuer != msg.sender) revert NotOriginalIssuer(msg.sender, b.issuer);
        if (b.revoked) revert AlreadyRevoked(root);
        b.revoked = true;
        emit BatchRevoked(root, msg.sender);
    }

    // ----------------------------------------------------------------- public

    /// @notice Free read-only check used by HR: returns the status of a document hash.
    function verify(bytes32 hash)
        external
        view
        returns (Status status, address issuer, uint64 issuedAt, uint64 expiresAt)
    {
        Credential memory c = _credentials[hash];
        if (c.issuer == address(0)) return (Status.NotFound, address(0), 0, 0);
        return (_statusOf(c.issuer, c.revoked, c.expiresAt), c.issuer, c.issuedAt, c.expiresAt);
    }

    /// @notice Verify one document that belongs to a batch, using its Merkle proof.
    function verifyInBatch(bytes32 root, bytes32 leaf, bytes32[] calldata proof)
        external
        view
        returns (Status status, address issuer)
    {
        Batch memory b = _batches[root];
        if (b.issuer == address(0) || !MerkleProof.verifyCalldata(proof, root, leaf)) {
            return (Status.NotFound, address(0));
        }
        return (_statusOf(b.issuer, b.revoked, 0), b.issuer);
    }

    function _statusOf(address issuer, bool revoked, uint64 expiresAt) private view returns (Status) {
        if (revoked) return Status.Revoked;
        if (!hasRole(ISSUER_ROLE, issuer)) return Status.IssuerSuspended;
        if (expiresAt != 0 && block.timestamp > expiresAt) return Status.Expired;
        return Status.Valid;
    }
}
