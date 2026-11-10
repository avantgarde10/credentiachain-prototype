#!/usr/bin/env bash
# Demo of the CredentiaChain prototype on a LOCAL Anvil network (test accounts only, no real funds).
# Educational project for the course Introduction to Finance.
# Not a real product, service or investment offer. Do not use with real funds.
set -euo pipefail
export PATH="/opt/foundry:$PATH"; USE=${SOLC_BIN:+--use $SOLC_BIN}
RPC=http://127.0.0.1:8545
# Anvil's pre-funded TEST accounts (unlocked, so no private key is typed anywhere)
ADMIN=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
UNIVERSITY=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
OUTSIDER=0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
say() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; sleep "${PAUSE:-1}"; }
status() { case "$1" in 0) echo NotFound;; 1) echo VALID;; 2) echo REVOKED;; 3) echo Expired;; 4) echo IssuerSuspended;; esac; }

say "1. Start a local development blockchain (Anvil, gas price 0 like our Besu network)"
anvil --silent --gas-price 0 --base-fee 0 >/tmp/anvil.log 2>&1 & ANVIL=$!
trap 'kill $ANVIL 2>/dev/null || true' EXIT
until cast block-number --rpc-url $RPC >/dev/null 2>&1; do sleep 0.3; done
echo "chain id: $(cast chain-id --rpc-url $RPC)"

say "2. Deploy CredentialRegistry (admin = consortium account)"
OUT=$(forge create src/CredentialRegistry.sol:CredentialRegistry $USE --rpc-url $RPC --unlocked --from $ADMIN --broadcast --constructor-args $ADMIN 2>&1)
echo "$OUT" | grep -E "Deployed to|Transaction hash"
REG=$(echo "$OUT" | awk '/Deployed to/{print $3}')

say "3. Admin approves 'Test University' as an issuer"
cast send $REG "registerIssuer(address,string)" $UNIVERSITY "Test University" --unlocked --from $ADMIN --rpc-url $RPC | grep -E "status|gasUsed"

say "4. Off-chain: compute the salted SHA-256 hash of an invented document (not the scan!)"
HASH=$(python3 offchain/hash_document.py demo-salt-123)
echo "hash = $HASH   (only this goes on-chain; no name, no IIN)"

say "5. University registers the hash"
cast send $REG "issueDocument(bytes32,bytes32,uint64)" $HASH $(cast keccak DIPLOMA) 0 --unlocked --from $UNIVERSITY --rpc-url $RPC | grep -E "status|gasUsed"

say "6. HR verifies the document (free read call)"
R=$(cast call $REG "verify(bytes32)(uint8,address,uint64,uint64)" $HASH --rpc-url $RPC | head -1); echo "result: $(status $R)"

say "7. HR verifies a FORGED document (different hash)"
FAKE=$(python3 offchain/hash_document.py wrong-salt)
R=$(cast call $REG "verify(bytes32)(uint8,address,uint64,uint64)" $FAKE --rpc-url $RPC | head -1); echo "result: $(status $R)"

say "8. An outsider tries to register a hash -> must fail (access control)"
if cast send $REG "issueDocument(bytes32,bytes32,uint64)" $FAKE $(cast keccak DIPLOMA) 0 --unlocked --from $OUTSIDER --rpc-url $RPC >/dev/null 2>&1; then echo "UNEXPECTED: accepted"; else echo "rejected: AccessControlUnauthorizedAccount"; fi

say "9. University revokes the document; HR checks again"
cast send $REG "revokeDocument(bytes32)" $HASH --unlocked --from $UNIVERSITY --rpc-url $RPC | grep -E "status"
R=$(cast call $REG "verify(bytes32)(uint8,address,uint64,uint64)" $HASH --rpc-url $RPC | head -1); echo "result: $(status $R)"

say "10. Run the unit tests"
forge test $USE --offline 2>&1 | grep -E "PASS|FAIL|Suite result"
