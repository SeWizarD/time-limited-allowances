# Fix status: audit 2026-09-26

> Commit hashes below refer to the development history. This repository contains the final, fixed code.

| ID | Severity | Title | Status | Fix commit | Regression test |
|---|---|---|---|---|---|
| APPROVE-1 | Medium | Unlimited approvals revert | Fixed | `ca58b5f` | `APPROVE1_maxUintApprove.t.sol` |
| PERMIT-2 | Medium | Revoking does not void signed permits | Fixed | `3ea8a12` | `PERMIT2_invalidateNonce.t.sol`, invariant fuzz |
| COMPAT-1 | Low | Zero-value transferFrom reverts | Fixed | `d55979a` | `COMPAT1_zeroValueTransferFrom.t.sol` |
| PERMIT-1 | Low | No EIP-2612 permit | Fixed | `d64942d` | `PERMIT_signatures.t.sol` |
| PERMIT-3 | Low | Expiring permit named `Permit` | Fixed | `d64942d` | `PERMIT_signatures.t.sol` |
| SPEC-1 | Low | Spec contradictions | Fixed | `c63d7c6` | n/a |
| REVIEW-1 | Low | Fake mint event from address(0) | Fixed | `df193ad` | `COMPAT1_zeroValueTransferFrom.t.sol` (REVIEW1) |
| PERMIT-4 | Info | No ERC-1271 | Fixed | `d64942d` | `PERMIT_signatures.t.sol` |
| REVIEW-2 | Info | Unbounded 1271 return copy | Fixed | `df193ad` | `PERMIT_signatures.t.sol` (REVIEW2) |
| INFO-1 | Info | Revocation stores any expiry | Fixed | `7b85bb3` | `COMPAT1_zeroValueTransferFrom.t.sol` (INFO1) |
| PERMIT-5 | Info | Permit front-running | Acknowledged | n/a | documented in SPEC |
| REVIEW-3 | Info | Fallback returning 1271 magic | Acknowledged | n/a | documented in SPEC |
| DESIGN-1 | Info | Long-lived integrations lose approvals | Acknowledged (by design) | n/a | documented in SPEC |
