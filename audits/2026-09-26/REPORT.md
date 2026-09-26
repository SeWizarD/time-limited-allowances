# ERC20Expiring security audit: 2026-09-26 (round 1)

> Commit hashes below refer to the development history. This repository contains the final, fixed code.

## Summary
ERC20Expiring is an ERC-20 where every allowance has an expiry: set explicitly with `approve(spender, value, expiresAt)`, or taken from the holder's own default duration for the plain `approve(spender, value)`. It has no admin, owner, upgradeability, pause or external dependencies. The audit found no way for anyone to take another holder's tokens without that holder's approval or signature. The worst issues were two Mediums:
- the standard "unlimited" approval reverted, breaking the spec's central compatibility promise;
- revoking an approval did not void a permit the holder had already signed.

All findings were fixed, except the ones listed under Owner decisions (which are by design). Every fix has a regression test.

| Severity | Found | Proven | Unproven |
|---|---|---|---|
| Critical | 0 | 0 | 0 |
| High | 0 | 0 | 0 |
| Medium | 2 | 2 | 0 |
| Low / Info | 11 | 7 | 4 (wallet display, design, documented behaviour) |

## Scope and coverage
- Commit audited: `b2229f3`. Fixes land in `ca58b5f`..`df193ad`, and the fix diff was re-audited.
- In scope: `src/ERC20Expiring.sol` (~150 nSLOC at start), `src/interfaces/IERC20Expiring.sol`, `src/ExpiringToken.sol`, `SPEC.md`. Out of scope: forge-std, deployment scripts (none), anything off-chain.
- Read line-by-line: all in-scope files, three times (the auditor plus two blind lens passes), and the fix diff once more by a fourth blind reviewer.
- Method:
  - one full manual pass plus two independent blind lens passes: (a) allowance lifecycle and ERC-20 compatibility, (b) signatures and EIP-712;
  - a fix-diff pass afterwards;
  - a Foundry proof of concept for every Medium and most Lows;
  - a stateful invariant fuzz suite: 256 runs × 500 calls per invariant, covering transfers, both approves, default changes, spends, both permits, nonce invalidation and time warps.
- slither ran: only timestamp-comparison, inline-assembly and naming notes, all expected for an expiry token with a bounded 1271 call.
- A deep run (20,000 fuzz runs; invariants 2,500 runs × 1,000 calls) ran after the fixes: all 25 tests passed, and all 4 invariants held over 2.5M calls each with 0 reverts.
- SPEC.md was exported to ERC format and passes `eipw` 0.11.0; the only errors left are the `eip` and `discussions-to` placeholders, which get filled on submission.
- Tools not run: aderyn and halmos are not installed on this machine.
- Baseline: 6/6 tests passing at `b2229f3`. Final: 25/25 passing, and runtime size is 8,887 B (limit 24,576).
- This audit does not show the absence of bugs. Not covered:
  - economic or market effects of expiring approvals on specific protocols;
  - behaviour inside real wallets' signing UIs;
  - deployment and key management;
  - any token built on the base contract that adds its own logic.

## System overview
Holders own balances, approve spenders and sign permits. Spenders call `transferFrom` within an allowance's value and before its expiry. Relayers submit signatures. There are no privileged roles and supply is fixed at construction. Key invariants, all fuzzed:
- supply is conserved;
- nothing is spent past its expiry or above its allowance;
- every live allowance lasts at most 365 days;
- defaults stay in range;
- a cancelled permit can never be used.

The full map is in `SYSTEM.md`.

## Findings

### APPROVE-1: Unlimited approvals revert [Medium] [Proven, Fixed]
**Where:** `src/ERC20Expiring.sol:_approve` (`if (value > type(uint192).max) revert ValueTooLarge()`).
**Invariant broken:** SPEC says the plain `approve` must not revert. Found independently by all three hunt passes.
**Attack:** a wallet or dApp calls `approve(router, type(uint256).max)` → reverts. `permit` with max value → reverts.
**Impact:** the most common approval in DeFi fails. Uniswap, aggregators, the MetaMask "max" option, Permit2 set-up and `SafeERC20.forceApprove(max)` all break, so the token is unusable across much of DeFi. No funds at risk.
**Fix:** `ca58b5f`: values above `uint192` max are stored as `uint192` max. They still expire and still decrease on spend. Regression: `test/audit20260926/APPROVE1_maxUintApprove.t.sol`.

### PERMIT-2: Revoking does not void signed permits [Medium] [Proven, Fixed]
**Where:** `approve(spender, 0)` does not touch `nonces`, and there was no way to invalidate a nonce.
**Attack:**
1. Alice signs a permit for S (30-day allowance, 1-day deadline).
2. She changes her mind and calls `approve(S, 0)`.
3. S submits the old signature → the allowance is back → S takes the funds.

**Impact:** a holder who believes they revoked access can still lose up to the signed value, until the signature's deadline.
**Fix:** `3ea8a12`: `invalidateNonce()` voids all outstanding signatures, and SPEC's Security Considerations tell holders to use it. Regression: `PERMIT2_invalidateNonce.t.sol`. Invariant `cancelledPermitUsed == 0` is fuzzed.

### COMPAT-1: Zero-value `transferFrom` reverts without allowance [Low] [Proven, Fixed]
ERC-20 tokens accept `transferFrom(a, b, 0)` from anyone. This token reverted `ApprovalExpired`, breaking aggregators and batchers that pull 0-amount legs. Fix `d55979a`: zero-value transfers skip the allowance. Regression: `COMPAT1_zeroValueTransferFrom.t.sol`.

### PERMIT-1: No standard EIP-2612 `permit` [Low] [Proven, Fixed]
Routers calling the 7-argument `permit` (e.g. `selfPermit`) hit a missing function. Tooling that probes for `nonces` and `DOMAIN_SEPARATOR` would wrongly assume EIP-2612 support. Fix `d64942d`: added EIP-2612 `permit`; its allowance expires after the owner's default duration. Regression: `PERMIT_signatures.t.sol`.

### PERMIT-3: Expiring permit reused the `Permit` type name [Low] [Unproven, Fixed]
Wallets that special-case `primaryType: "Permit"` may render only the value and deadline, hiding the expiry from the signer. Not reproduced in a real wallet. Fix `d64942d`: the type is now `ExpiringPermit`, and the two signature types cannot be confused (tested).

### SPEC-1: Spec contradicted itself and the code [Low] [Fixed]
- The "MUST NOT revert" rule versus the "values above uint192 are rejected" rule.
- The zero spender reverts despite "MUST NOT revert".
- The "timestamp not duration" rationale was false for the plain `approve`, whose expiry counts from inclusion.
- The in-repo interface lacked `MAX_APPROVAL_DURATION()`.

Fix `c63d7c6` (and the interface in `d64942d`).

### REVIEW-1: Zero-value `transferFrom` from address(0) emitted a fake mint event [Low] [Proven, Fixed]
Introduced by the COMPAT-1 fix, found in the fix-diff review. `transferFrom(address(0), x, 0)` emitted `Transfer(0x0, x, 0)`, which indexers read as a mint. Fix `df193ad`: `_transfer` rejects `from == address(0)`. Regression: `REVIEW1` in `COMPAT1_zeroValueTransferFrom.t.sol`.

### PERMIT-4: Contract wallets could not use permit [Info] [Fixed]
Safe-style wallets had no ERC-1271 path. Fix `d64942d`: ECDSA is checked first, then ERC-1271, so EIP-7702 accounts (which have code) still verify by key. Tests cover a 1271 wallet, a foreign signature and a delegated EOA.

### REVIEW-2: ERC-1271 check copied unbounded return data [Info] [Proven, Fixed]
A contract owner returning megabytes from `isValidSignature` made relayers pay for copying all of it. Fix `df193ad`: only the first 32 bytes are copied. Regression: `REVIEW2` in `PERMIT_signatures.t.sol`.

### INFO-1: Revocations stored any expiry [Info] [Fixed]
`approve(s, 0, type(uint64).max)` stored and emitted a far-future expiry, which dashboards could show as a live approval. Fix `7b85bb3`: revocations store expiry 0.

### PERMIT-5: Permit front-running [Info] [Acknowledged]
The standard EIP-2612 issue: a copied signature submitted first makes an integrator's transaction revert. The allowance still ends up as signed. Documented in SPEC with the try/catch guidance.

### REVIEW-3: A contract whose fallback returns the 1271 magic word approves everything it owns [Info] [Acknowledged]
Only that contract's own balance is exposed. Documented in SPEC ("the wallet alone decides").

### DESIGN-1: Long-lived integrations lose their approvals [Info] [Acknowledged, owner decision]
Vaults and routers that approve once at deployment, and Permit2 users on the default duration, stop working when the approval expires. This is the point of the token. A per-token allowlist of "never expire" spenders was suggested and rejected, because it re-creates the risk the token exists to remove. Holders can raise their own default to 365 days. Documented in SPEC Backwards Compatibility.

## Centralisation and trust
None. There is no owner, admin, minter, pauser, upgrade path or fee switch. Supply is fixed at deployment in `ExpiringToken`. Tokens built on the abstract base can add privileges; those need their own review.

## Owner decisions
- DESIGN-1: no allowlist for non-expiring spenders (kept out deliberately).
- Fallback duration 1 day and cap 365 days are constants; change them before deployment if wanted.

## Previously reported issues
None; this is the first round.

## Appendix A: Refuted leads
| Lead | Why it doesn't work |
|---|---|
| Unchecked `a.value -= uint192(value)` truncates | `a.value < value` is compared in uint256 first; values above uint192 max revert `InsufficientAllowance` |
| `expiresAt - block.timestamp` underflow | Guarded by the `expiresAt <= block.timestamp` revert before it |
| `uint64(block.timestamp) + duration` overflow | Duration ≤ 365 days; overflows in year ~5.8×10^11 |
| Signature replay across chains | `DOMAIN_SEPARATOR` rebuilds when `block.chainid` changes |
| High-s malleation | Low-s bound enforced (tested) |
| `ecrecover` returning 0 matches `owner == 0` | `signer != address(0)` required; address 0 has no code for 1271 |
| Confusing the two permit types | Distinct typehashes; cross-use reverts (tested) |
| Self-transfer mints or burns | `_transfer` reads `bal`, writes `bal - value`, then adds to the same slot: net zero |
| Setting default 0 disables expiry | 0 resolves to the 1-day fallback (fuzzed) |
| Third party changes someone's default or allowance | Only `msg.sender` or a valid owner signature writes either (fuzzed) |

## Appendix B: Low-priority notes
- `approve` overwrites, so the classic ERC-20 change-of-allowance race still exists. SPEC advises revoking first.
- Expiries shorter than about a minute are not reliable, because validators can shift `block.timestamp` slightly.
