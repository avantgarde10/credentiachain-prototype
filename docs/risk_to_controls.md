# From risks to controls in the prototype

Educational project for the course Introduction to Finance. Not a real product, service or investment offer.

| Risk (report Section 3) | Control in the contract | Test in `test/CredentialRegistry.t.sol` |
|---|---|---|
| Outsider registers fake documents | Only accounts with the issuer role can issue | `test_OnlyIssuerCanIssue` |
| Anyone can approve themselves as issuer | Only the administrator can register issuers | `test_OnlyAdminCanRegisterIssuer` |
| Existing record is overwritten | Duplicate hash is rejected | `test_DuplicateHashReverts` |
| Another issuer revokes a record | Only the original issuer can revoke | `test_RevokeOnlyByOriginalIssuer` |
| Stolen issuer key | Administrator can suspend the issuer; its documents stop being valid | `test_SuspendedIssuerDocumentsNotValid` |
| Emergency or bug found | Administrator can pause issuance; verification still works | `test_PauseBlocksIssueButNotVerify` |
| Old documents stay valid | Expiry date is checked on verification | `test_ExpiredDocument` |
| Unknown hash is accepted | Unknown hash returns NotFound | `test_UnknownHashIsNotFound`, fuzz test |
