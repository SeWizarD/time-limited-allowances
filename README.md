# ERC20Expiring: tokens where every approval expires

Every allowance has an expiry, at most 365 days away, and `allowance()` reads 0 once it expires. `approve(spender, value, expiresAt)` sets an exact expiry. The plain ERC-20 `approve(spender, value)` still works and uses the holder's own default duration (1 day unless the holder changes it with `setDefaultApprovalDuration`). Signed approvals work through both the standard ERC-2612 `permit` and an `ExpiringPermit` that signs the expiry; contract wallets are supported via ERC-1271. `invalidateNonce()` voids unsubmitted signatures. The full spec is in [SPEC.md](SPEC.md).

    forge build && forge test
