// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {CredentialRegistry} from "../src/CredentialRegistry.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/// Educational project for the course Introduction to Finance. Test data is invented.
contract CredentialRegistryTest is Test {
    CredentialRegistry reg;
    address admin = makeAddr("admin"); // test accounts only
    address university = makeAddr("university");
    address employer = makeAddr("employer");
    address outsider = makeAddr("outsider");

    bytes32 constant DIPLOMA = keccak256("DIPLOMA");
    // SHA-256 uses a precompile call, so the hashes are computed once in setUp (not as constants):
    // a constant would be re-evaluated at every use and consume vm.prank().
    bytes32 H1;
    bytes32 H2;

    function setUp() public {
        H1 = sha256("TEST-DOC-0001|BIN000000000|IIN-FAKE-0001|2026-06-30|salt-aaa");
        H2 = sha256("TEST-DOC-0002|BIN000000000|IIN-FAKE-0002|2026-06-30|salt-bbb");
        reg = new CredentialRegistry(admin);
        vm.startPrank(admin);
        reg.registerIssuer(university, "Test University");
        reg.registerIssuer(employer, "Test Employer LLP");
        vm.stopPrank();
    }

    // 1. Main use case: issue then verify -> Valid
    function test_IssueThenVerifyIsValid() public {
        vm.prank(university);
        reg.issueDocument(H1, DIPLOMA, 0);
        (CredentialRegistry.Status s, address issuer,,) = reg.verify(H1);
        assertEq(uint8(s), uint8(CredentialRegistry.Status.Valid));
        assertEq(issuer, university);
    }

    // 2. Unknown hash -> NotFound (a forged document is simply not on the ledger)
    function test_UnknownHashIsNotFound() public view {
        (CredentialRegistry.Status s,,,) = reg.verify(H2);
        assertEq(uint8(s), uint8(CredentialRegistry.Status.NotFound));
    }

    // 3. Access control: an outsider and even the admin cannot issue documents
    function test_OnlyIssuerCanIssue() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, outsider, reg.ISSUER_ROLE())
        );
        vm.prank(outsider);
        reg.issueDocument(H1, DIPLOMA, 0);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, admin, reg.ISSUER_ROLE())
        );
        vm.prank(admin);
        reg.issueDocument(H1, DIPLOMA, 0);
    }

    // 4. Only the admin can approve issuers
    function test_OnlyAdminCanRegisterIssuer() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, outsider, reg.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(outsider);
        reg.registerIssuer(outsider, "Fake University");
    }

    // 5. The same hash cannot be registered twice (no overwriting by another issuer)
    function test_DuplicateHashReverts() public {
        vm.prank(university);
        reg.issueDocument(H1, DIPLOMA, 0);
        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.AlreadyRegistered.selector, H1));
        vm.prank(employer);
        reg.issueDocument(H1, DIPLOMA, 0);
    }

    // 6. Only the original issuer can revoke; after revocation the status is Revoked
    function test_RevokeOnlyByOriginalIssuer() public {
        vm.prank(university);
        reg.issueDocument(H1, DIPLOMA, 0);

        vm.expectRevert(
            abi.encodeWithSelector(CredentialRegistry.NotOriginalIssuer.selector, employer, university)
        );
        vm.prank(employer);
        reg.revokeDocument(H1);

        vm.prank(university);
        reg.revokeDocument(H1);
        (CredentialRegistry.Status s,,,) = reg.verify(H1);
        assertEq(uint8(s), uint8(CredentialRegistry.Status.Revoked));
    }

    // 7. Stolen issuer key: admin suspends the issuer, its documents stop being Valid
    function test_SuspendedIssuerDocumentsNotValid() public {
        vm.prank(university);
        reg.issueDocument(H1, DIPLOMA, 0);
        vm.prank(admin);
        reg.suspendIssuer(university);

        (CredentialRegistry.Status s,,,) = reg.verify(H1);
        assertEq(uint8(s), uint8(CredentialRegistry.Status.IssuerSuspended));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, university, reg.ISSUER_ROLE()
            )
        );
        vm.prank(university);
        reg.issueDocument(H2, DIPLOMA, 0);
    }

    // 8. Expiry date (e.g. a work certificate valid for 90 days)
    function test_ExpiredDocument() public {
        vm.prank(employer);
        reg.issueDocument(H1, keccak256("EMPLOYMENT_CERT"), uint64(block.timestamp + 90 days));
        vm.warp(block.timestamp + 91 days);
        (CredentialRegistry.Status s,,,) = reg.verify(H1);
        assertEq(uint8(s), uint8(CredentialRegistry.Status.Expired));
    }

    // 9. Emergency pause blocks issuing, but verification still works
    function test_PauseBlocksIssueButNotVerify() public {
        vm.prank(university);
        reg.issueDocument(H1, DIPLOMA, 0);
        vm.prank(admin);
        reg.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(university);
        reg.issueDocument(H2, DIPLOMA, 0);

        (CredentialRegistry.Status s,,,) = reg.verify(H1);
        assertEq(uint8(s), uint8(CredentialRegistry.Status.Valid));
    }

    // 10. Batch issuance: one transaction for a whole graduation, verified by Merkle proof
    function test_BatchIssueAndMerkleVerification() public {
        bytes32 l0 = sha256("batch-doc-0");
        bytes32 l1 = sha256("batch-doc-1");
        bytes32 root = _pairHash(l0, l1); // two-leaf Merkle tree (sorted pairs, as in OpenZeppelin)

        bytes32 forged = sha256("forged-doc");
        vm.prank(university);
        reg.issueBatch(root, 2);

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = l1;
        (CredentialRegistry.Status s, address issuer) = reg.verifyInBatch(root, l0, proof);
        assertEq(uint8(s), uint8(CredentialRegistry.Status.Valid));
        assertEq(issuer, university);

        // a leaf that is not in the tree is rejected
        (CredentialRegistry.Status s2,) = reg.verifyInBatch(root, forged, proof);
        assertEq(uint8(s2), uint8(CredentialRegistry.Status.NotFound));

        // revoking the batch invalidates all its documents
        vm.prank(university);
        reg.revokeBatch(root);
        (CredentialRegistry.Status s3,) = reg.verifyInBatch(root, l0, proof);
        assertEq(uint8(s3), uint8(CredentialRegistry.Status.Revoked));
    }

    // 11. Fuzz: a random hash that was never issued is never Valid
    function testFuzz_RandomHashNeverValid(bytes32 randomHash) public {
        vm.assume(randomHash != H1);
        vm.prank(university);
        reg.issueDocument(H1, DIPLOMA, 0);
        (CredentialRegistry.Status s,,,) = reg.verify(randomHash);
        assertEq(uint8(s), uint8(CredentialRegistry.Status.NotFound));
    }

    function _pairHash(bytes32 a, bytes32 b) private pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }
}
