# System map: ERC20Expiring @ b2229f3

## Actors
- **Holder**: owns balance; approves spenders; sets own default approval duration; signs permits.
- **Spender**: any address with an unexpired allowance; calls `transferFrom`.
- **Relayer**: anyone submitting a holder's permit signature.
- No admin, owner, pause, mint after deploy, upgradeability or external calls. Supply is fixed at construction (`ExpiringToken`).

## Asset flows
- `transfer`: holder → recipient.
- `transferFrom`: holder → recipient, by spender, bounded by the allowance value and expiry.
- `_mint`: constructor only in the example token.

## State ledgers
| State | Written by |
|---|---|
| `balanceOf`, `totalSupply` | `_transfer`, `_mint` |
| `_allowances[o][s] = {value:uint192, expiresAt:uint64}` | `_approve` (via both `approve`s, `permit`), `transferFrom` (value only) |
| `_defaultDuration[o]` | `setDefaultApprovalDuration` |
| `nonces[o]` | `permit` |

## Invariants
1. Sum of balances == totalSupply.
2. A spender can move at most `value` of the holder's tokens per approval, and only while `block.timestamp < expiresAt`.
3. After expiry, `allowance()` == 0 and `transferFrom` reverts for any positive amount.
4. Every non-zero allowance has `expiresAt - timeSet <= MAX_APPROVAL_DURATION`.
5. `approve(spender, value)` never reverts for a valid spender (spec MUST); expiry = now + holder default.
6. Holder default is in (0, MAX] after resolution (0 stored → fallback 1 day).
7. `transferFrom` never extends or resets the expiry.
8. Only the holder can create or change their allowances (direct call or valid signature).
9. A permit signature is usable once, on one chain and one contract, only before `deadline`.
10. Malleated (high-s) signatures are rejected.
11. Revocation (value 0) always succeeds regardless of the expiry passed.
12. `allowance()` and `transferFrom` agree on the expiry boundary (valid iff `now < expiresAt`).
13. No path lets a third party change a holder's default duration or allowance.

## External dependencies
None: no oracles, no external calls, no hooks. Integrations that matter for compatibility: wallets and dApps calling `approve(address,uint256)` (often with `type(uint256).max`), OpenZeppelin SafeERC20, EIP-2612 permit tooling.
