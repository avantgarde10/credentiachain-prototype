> **Educational project for the course Introduction to Finance. Not a real product, service or investment offer. Do not use with real funds.**

# CredentiaChain: prototype of the verification smart contract

Team NN · Final Project · demo video: `[DEMO VIDEO LINK]` · testnet contract address: none (local network only)

CredentiaChain lets approved organisations (universities, employers) register **only salted SHA-256 hashes** of documents, and lets anyone check a hash. No names, IIN, files or funds are stored on the blockchain. This repository is the prototype of the core use case: *issue → verify → revoke*.

## What is inside

| Path | What it is |
|---|---|
| `src/CredentialRegistry.sol` | The smart contract (Solidity 0.8.28, OpenZeppelin `AccessControl`, `Pausable`, `MerkleProof`) |
| `test/CredentialRegistry.t.sol` | 11 unit tests (10 normal + 1 fuzz test), all passing |
| `offchain/hash_document.py` | Builds the canonical text of a document and its salted hash (invented data only) |
| `offchain/test_hash_document.py` | 3 unit tests for the hashing helper |
| `scripts/demo.sh` | Full demo on a local Anvil network, ends with the unit tests |

Roles: `DEFAULT_ADMIN_ROLE` (a consortium multisignature wallet in production) approves and suspends issuers and can pause the contract; `ISSUER_ROLE` can register documents and revoke **its own** documents; **verification is public and free** (read-only call).
Functions: `registerIssuer`, `suspendIssuer`, `issueDocument`, `issueBatch` (one Merkle root for a whole graduation), `revokeDocument`, `revokeBatch`, `verify`, `verifyInBatch`, `pause`, `unpause`.

## Run it on your computer (local network, test accounts only)

1. Install Foundry (contains `forge` and `anvil`): <https://book.getfoundry.sh/getting-started/installation>
2. Install the libraries (they are not copied into the repository):
   ```bash
   git init            # only if this folder is not a git repository yet
   forge install OpenZeppelin/openzeppelin-contracts@v5.1.0 foundry-rs/forge-std
   ```
3. Run the unit tests: `forge test -vv` (add `--gas-report` for gas costs)
4. Run the full demo (starts Anvil by itself, deploys, issues, verifies, revokes, runs tests): `./scripts/demo.sh`
5. Python helper tests: `cd offchain && python3 -m unittest -v`

Anvil starts with test accounts that the tool creates. Do **not** use a wallet that holds real assets, never put a private key in the code, and never deploy to a main network. If you ever use a key, keep it in a `.env` file (already in `.gitignore`).

## Test results (measured on a local network)

All 11 Foundry tests pass. Typical gas: `issueDocument` ≈ 76,000, `issueBatch` ≈ 53,000 (a whole graduation), `revokeDocument` ≈ 38,000, `verify` ≈ 7,000 (read-only, free). On our Besu network the gas price is 0.

## Credits

Open-source code: [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) v5.1.0 (MIT licence) and [forge-std](https://github.com/foundry-rs/forge-std) (MIT / Apache-2.0). AI tools used are listed in the AI Disclosure Statement of the report.
