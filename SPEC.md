---
title: Time-Limited Token Allowances
description: Fungible tokens whose allowances always expire, by holder-chosen time or holder default
author: SeWizarD (@SeWizarD)
discussions-to: DISCUSSIONS_URL
status: Draft
type: Standards Track
category: ERC
created: 2026-09-26
requires: 20, 712, 1271, 2612
---

## Abstract

This standard defines a fungible token that follows [ERC-20](https://eips.ethereum.org/EIPS/eip-20) for balances and transfers but changes how approvals work. Every allowance has an expiry timestamp. Holders can set it on each approval, or rely on a default duration they choose for themselves, which the plain ERC-20 `approve` uses. There is no approval that lasts forever. Once an allowance expires, it cannot be spent and reads as zero. The standard also includes a signature-based approval (`permit`) that signs over the expiry, so gasless approvals get the same guarantee.

## Motivation

Approvals are the most common way tokens are lost. Under ERC-20 an approval never expires: an allowance granted years ago to a contract that later turns malicious or is exploited can still drain the holder's balance. Interfaces make this worse by requesting unlimited amounts to save users a repeat transaction.

Revoking approvals by hand does not work in practice. Users forget, revocation costs gas, and most holders never check what they have approved. The safe behaviour has to be the default:

- Every approval ends. How long it lasts is capped by the token.
- Approvals made through the plain ERC-20 `approve` expire after a duration the holder controls, so existing wallets and dApps keep working and still cannot create an approval that never expires.
- Holders who want finer control set an exact end time per approval.
- Signed approvals carry the same expiry, so gasless flows cannot bypass the rule.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Interface

```solidity
interface IERC20Expiring {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event ApprovalExpiring(address indexed owner, address indexed spender, uint256 value, uint64 expiresAt);
    event DefaultApprovalDurationSet(address indexed owner, uint64 duration);
    event NonceInvalidated(address indexed owner, uint256 nonce);

    error ApprovalExpired(address owner, address spender, uint64 expiredAt);
    error ExpiryInPast(uint64 expiresAt);
    error DurationTooLong(uint64 duration);

    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);

    function approve(address spender, uint256 value) external returns (bool);
    function approve(address spender, uint256 value, uint64 expiresAt) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function allowanceWithExpiry(address owner, address spender)
        external view returns (uint256 value, uint64 expiresAt);

    function defaultApprovalDuration(address owner) external view returns (uint64);
    function setDefaultApprovalDuration(uint64 duration) external;

    function permit(
        address owner, address spender, uint256 value,
        uint256 deadline, uint8 v, bytes32 r, bytes32 s
    ) external;
    function permit(
        address owner, address spender, uint256 value, uint64 expiresAt,
        uint256 deadline, uint8 v, bytes32 r, bytes32 s
    ) external;
    function nonces(address owner) external view returns (uint256);
    function invalidateNonce() external;
    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function MAX_APPROVAL_DURATION() external view returns (uint64);
}
```

`totalSupply`, `balanceOf`, `transfer` and the `Transfer` event behave exactly as in ERC-20.

### Default approval duration

Each holder has a default approval duration.

- `setDefaultApprovalDuration(duration)` sets the caller's default. It MUST revert with `DurationTooLong` if `duration > MAX_APPROVAL_DURATION()`, and MUST emit `DefaultApprovalDurationSet(owner, duration)`. Setting 0 restores the token's fallback.
- `defaultApprovalDuration(owner)` returns the holder's default, or the token's fallback duration if none is set. The fallback is fixed by each token, MUST be greater than 0 and no more than `MAX_APPROVAL_DURATION()`. This document recommends 1 day.

### Plain ERC-20 approve

`approve(spender, value)` MUST behave exactly as `approve(spender, value, block.timestamp + defaultApprovalDuration(msg.sender))` and return `true`. Because the resulting expiry is always within bounds, it MUST NOT revert for any `value`. The only permitted revert is `spender == address(0)`, as in common ERC-20 implementations. This is what makes existing wallets, dApps and routers keep working, while no approval they create lasts forever.

The expiry is counted from the block that includes the transaction, not from when the holder signed it.

### Approval

`approve(spender, value, expiresAt)` sets the caller's allowance for `spender` to `value`, replacing any existing allowance, and valid while `block.timestamp < expiresAt`.

- Values above `type(uint192).max` MUST be stored as `type(uint192).max`, not rejected, so "unlimited" approvals from existing tooling still succeed (and still expire).
- If `value > 0`:
  - it MUST revert with `ExpiryInPast` if `expiresAt <= block.timestamp`.
  - it MUST revert with `DurationTooLong` if `expiresAt - block.timestamp > MAX_APPROVAL_DURATION()`.
- If `value == 0` (a revocation), `expiresAt` MUST NOT be checked, and the stored expiry MUST be 0.
- It MUST emit `Approval(owner, spender, value)` and then `ApprovalExpiring(owner, spender, value, expiresAt)`, using the stored value and expiry.

`MAX_APPROVAL_DURATION()` is a constant fixed by each token and MUST be finite. This document recommends 365 days or less.

### Reading allowances

- `allowance(owner, spender)` MUST return 0 when `block.timestamp >= expiresAt`, and the remaining value otherwise.
- `allowanceWithExpiry(owner, spender)` MUST return the value on the same rule and the stored `expiresAt`, even if that time has passed.

### Spending

`transferFrom(from, to, value)` with `value == 0` MUST succeed without reading or changing the allowance, as in ERC-20. For `value > 0` it MUST:

1. revert with `ApprovalExpired(from, msg.sender, expiresAt)` if `block.timestamp >= expiresAt`;
2. revert if the remaining allowance is below `value`;
3. subtract `value` from the allowance and leave `expiresAt` unchanged;
4. perform the transfer as ERC-20 does.

No allowance value is treated as unlimited. Every spend reduces the allowance.

### Permit

Two signed approvals share one nonce sequence and one [EIP-712](https://eips.ethereum.org/EIPS/eip-712) domain, `EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)` with version `"1"`.

**Expiring permit.** `permit(owner, spender, value, expiresAt, deadline, v, r, s)` behaves as `approve(spender, value, expiresAt)` called by `owner`. Its typed data is:

```
ExpiringPermit(address owner,address spender,uint256 value,uint64 expiresAt,uint256 nonce,uint256 deadline)
```

The type is deliberately not named `Permit`, so wallets that special-case [ERC-2612](https://eips.ethereum.org/EIPS/eip-2612) do not hide the expiry from the signer.

**ERC-2612 permit.** `permit(owner, spender, value, deadline, v, r, s)` with the standard `Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)` type behaves as `approve(spender, value)` called by `owner`: the allowance expires after the owner's default duration, counted from inclusion.

For both:

- `deadline` limits how long the signature can be submitted. The allowance's expiry is separate.
- It MUST revert if `block.timestamp > deadline`.
- The signature is valid if it is a low-`s` ECDSA signature recovering to `owner`, or, when that fails and `owner` has code, if `owner` returns the [ERC-1271](https://eips.ethereum.org/EIPS/eip-1271) magic value from `isValidSignature(digest, abi.encodePacked(r, s, v))`. Checking ECDSA first keeps [EIP-7702](https://eips.ethereum.org/EIPS/eip-7702) accounts, which have code, working by key.
- It MUST consume `nonces[owner]`.
- `DOMAIN_SEPARATOR` MUST be recomputed if `block.chainid` differs from the chain the contract was deployed on.

`invalidateNonce()` MUST consume the caller's current nonce and emit `NonceInvalidated(owner, nonce)`. It voids every signed permit not yet submitted. Revoking with `approve(spender, 0)` does not, because a leaked signature could re-create the allowance.

## Rationale

**Timestamp, not duration.** With `approve(spender, value, expiresAt)` and the expiring permit, a transaction that sits in the mempool cannot end up with a later expiry than the user saw. The time the user signs is the time the allowance ends. The ERC-20 `approve` and ERC-2612 `permit` cannot carry a timestamp, so they count the holder's default from inclusion; this is bounded by `MAX_APPROVAL_DURATION` plus the time the transaction waits.

**Keeping the two-argument `approve`.** Reverting it would break every existing wallet, DEX and router. Instead, it keeps its signature and gains an expiry from the holder's own default. Integrations keep working unchanged, and the holder, not the dApp, decides how long those approvals last.

**Default per holder, not per token.** Holders use tokens in different ways. Someone who trades often may accept a week; a cold wallet may want ten minutes. The token supplies a short fallback so holders who never configure anything are still protected.

**Reading zero after expiry.** Aggregators, wallets and approval dashboards already read `allowance()`. Returning 0 means they show an expired approval as gone without any changes.

**No unlimited sentinel.** Treating `type(uint256).max` as never decreasing would let a large "unlimited" allowance last until its expiry. Every spend decreases the allowance, so the amount and the time both stay bounded.

**Storage.** A 192-bit amount and a 64-bit expiry fit in one storage slot, so the expiry adds no extra storage cost compared with ERC-20. Values above `type(uint192).max`, about 6.3 × 10^57, are stored as that maximum. No real supply comes near it, and clamping keeps `approve(spender, type(uint256).max)` working.

## Backwards Compatibility

The token implements the full ERC-20 interface. Every ERC-20 function keeps its signature and return values, and `approve(address,uint256)` succeeds as before. The one change in behaviour is that allowances expire:

- Contracts that assume an allowance lasts until revoked (routers and vaults that approve once) will see it expire and must approve again, per use or for no longer than they need.
- `allowance()` falling to 0 without an event is new. Indexers that track allowances from events should use `ApprovalExpiring` to learn the expiry.
- `allowance()` after `approve(spender, type(uint256).max)` reads `type(uint192).max`. Code that checks `allowance == type(uint256).max` to detect "unlimited" will re-approve, which is harmless.
- Both the ERC-2612 `permit` selector and ERC-1271 wallets are supported, so gasless tooling keeps working.
- A protocol contract that holds this token and approves another contract once at deployment, then never again, will stop working when that approval expires. Such contracts need a way to re-approve, or must be written against the expiring `approve`.

## Test Cases

The reference implementation ships a Foundry suite covering every rule above:
- expiry boundaries, and the plain `approve` using the holder default;
- clamping of values above `type(uint192).max`;
- zero-value transfers;
- both permit types, rejection of cross-type signatures, and `invalidateNonce`;
- ERC-1271 wallets, delegated EOAs and high-`s` rejection.

A stateful invariant fuzz suite checks four properties: supply conservation, no spend past expiry or above allowance, every live allowance within `MAX_APPROVAL_DURATION`, and no cancelled permit ever used.

## Reference Implementation

[`ERC20Expiring.sol`](src/ERC20Expiring.sol) (abstract base), [`IERC20Expiring.sol`](src/interfaces/IERC20Expiring.sol) (interface) and [`ExpiringToken.sol`](src/ExpiringToken.sol) (example token).

## Security Considerations

- **Front-running a change of allowance.** Like ERC-20, `approve` overwrites the allowance, so a spender watching the mempool can spend the old allowance before the new one lands. Holders should revoke with value 0 first, or approve only the amount needed right now.
- **Clock trust.** Expiry uses `block.timestamp`. Validators can move it by a few seconds, so expiries shorter than about one minute are not reliable.
- **Signed approvals.** A permit signature can be submitted by anyone until `deadline`, even after the holder revoked with `approve(spender, 0)`. Keep `deadline` short, and call `invalidateNonce()` to void signatures that were handed out but not used. The allowance's expiry still limits the damage if a signature leaks.
- **Permit front-running.** Anyone can submit a permit seen in the mempool first, making the integrator's own `permit` call revert. The allowance still ends up as signed. Integrators should wrap `permit` in try/catch and check `allowance()` afterwards.
- **Contract wallets.** For ERC-1271 owners, the wallet alone decides whether a signature is valid. A wallet that accepts anything exposes only its own balance.
- **Near-expiry spends.** A spender can use the whole allowance up to the last second before `expiresAt`. The expiry limits for how long a spender can act, not what it does before then.

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
