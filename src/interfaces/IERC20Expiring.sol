// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

/// @notice ERC-20 where every allowance carries an expiry. The plain ERC-20 `approve` uses the
/// owner's default duration. `allowance()` reads 0 once the expiry has passed.
interface IERC20Expiring is IERC20 {
    event ApprovalExpiring(address indexed owner, address indexed spender, uint256 value, uint64 expiresAt);
    event DefaultApprovalDurationSet(address indexed owner, uint64 duration);
    event NonceInvalidated(address indexed owner, uint256 nonce);

    error ApprovalExpired(address owner, address spender, uint64 expiredAt);
    error ExpiryInPast(uint64 expiresAt);
    error DurationTooLong(uint64 duration);

    /// @dev Approval valid while `block.timestamp < expiresAt`.
    function approve(address spender, uint256 value, uint64 expiresAt) external returns (bool);

    /// @return value 0 if expired
    /// @return expiresAt the stored expiry, even if already passed
    function allowanceWithExpiry(address owner, address spender) external view returns (uint256 value, uint64 expiresAt);

    /// @notice Lifetime given to approvals made through `approve(spender, value)`.
    function defaultApprovalDuration(address owner) external view returns (uint64);
    function setDefaultApprovalDuration(uint64 duration) external;

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint64 expiresAt,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    function nonces(address owner) external view returns (uint256);
    /// @notice Voids every permit the caller has signed but not yet had submitted.
    function invalidateNonce() external;
    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function MAX_APPROVAL_DURATION() external view returns (uint64);
}
