// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20Expiring} from "./interfaces/IERC20Expiring.sol";

interface IERC1271 {
    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4);
}

abstract contract ERC20Expiring is IERC20Expiring {
    struct Allowance {
        uint192 value;
        uint64 expiresAt;
    }

    bytes32 public constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant EXPIRING_PERMIT_TYPEHASH = keccak256(
        "ExpiringPermit(address owner,address spender,uint256 value,uint64 expiresAt,uint256 nonce,uint256 deadline)"
    );
    uint64 public constant FALLBACK_APPROVAL_DURATION = 1 days;
    uint64 public constant MAX_APPROVAL_DURATION = 365 days;

    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) public nonces;
    mapping(address => mapping(address => Allowance)) private _allowances;
    mapping(address => uint64) private _defaultDuration;

    uint256 private immutable _chainId;
    bytes32 private immutable _domainSeparator;

    error InsufficientBalance();
    error InsufficientAllowance();
    error ZeroAddress();
    error PermitExpired();
    error InvalidSignature();

    constructor(string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;
        _chainId = block.chainid;
        _domainSeparator = _buildDomainSeparator();
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        if (value != 0) {
            Allowance storage a = _allowances[from][msg.sender];
            if (a.expiresAt <= block.timestamp) revert ApprovalExpired(from, msg.sender, a.expiresAt);
            if (a.value < value) revert InsufficientAllowance();
            unchecked {
                a.value -= uint192(value);
            }
        }
        _transfer(from, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        _approve(msg.sender, spender, value, uint64(block.timestamp) + defaultApprovalDuration(msg.sender));
        return true;
    }

    function approve(address spender, uint256 value, uint64 expiresAt) external returns (bool) {
        _approve(msg.sender, spender, value, expiresAt);
        return true;
    }

    function allowance(address owner, address spender) external view returns (uint256 value) {
        (value,) = allowanceWithExpiry(owner, spender);
    }

    function allowanceWithExpiry(address owner, address spender) public view returns (uint256, uint64) {
        Allowance memory a = _allowances[owner][spender];
        return (a.expiresAt > block.timestamp ? a.value : 0, a.expiresAt);
    }

    function defaultApprovalDuration(address owner) public view returns (uint64) {
        uint64 d = _defaultDuration[owner];
        return d == 0 ? FALLBACK_APPROVAL_DURATION : d;
    }

    function setDefaultApprovalDuration(uint64 duration) external {
        if (duration > MAX_APPROVAL_DURATION) revert DurationTooLong(duration);
        _defaultDuration[msg.sender] = duration;
        emit DefaultApprovalDurationSet(msg.sender, duration);
    }

    /// @notice EIP-2612 permit. The approval expires after the owner's default duration.
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
    {
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline));
        _verify(owner, structHash, deadline, v, r, s);
        _approve(owner, spender, value, uint64(block.timestamp) + defaultApprovalDuration(owner));
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint64 expiresAt,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        _verify(owner, _expiringPermitHash(owner, spender, value, expiresAt, deadline), deadline, v, r, s);
        _approve(owner, spender, value, expiresAt);
    }

    function invalidateNonce() external {
        emit NonceInvalidated(msg.sender, nonces[msg.sender]++);
    }

    function _expiringPermitHash(address owner, address spender, uint256 value, uint64 expiresAt, uint256 deadline)
        private
        returns (bytes32)
    {
        return
            keccak256(abi.encode(EXPIRING_PERMIT_TYPEHASH, owner, spender, value, expiresAt, nonces[owner]++, deadline));
    }

    /// @dev EOA signature first, then ERC-1271, so EIP-7702 accounts with delegated code still verify by key.
    function _verify(address owner, bytes32 structHash, uint256 deadline, uint8 v, bytes32 r, bytes32 s) private view {
        if (block.timestamp > deadline) revert PermitExpired();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash));
        if (uint256(s) <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            address signer = ecrecover(digest, v, r, s);
            if (signer != address(0) && signer == owner) return;
        }
        if (owner.code.length != 0 && _isValid1271(owner, digest, abi.encodePacked(r, s, v))) return;
        revert InvalidSignature();
    }

    /// @dev Copies only the first return word, so a wallet cannot make the caller pay for a huge return.
    function _isValid1271(address wallet, bytes32 digest, bytes memory sig) private view returns (bool valid) {
        bytes memory data = abi.encodeWithSelector(IERC1271.isValidSignature.selector, digest, sig);
        bytes32 word;
        bool ok;
        assembly ("memory-safe") {
            ok := staticcall(gas(), wallet, add(data, 32), mload(data), 0, 32)
            word := mload(0)
            valid := and(ok, gt(returndatasize(), 31))
        }
        return valid && word == bytes32(IERC1271.isValidSignature.selector);
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return block.chainid == _chainId ? _domainSeparator : _buildDomainSeparator();
    }

    function _approve(address owner, address spender, uint256 value, uint64 expiresAt) internal {
        if (spender == address(0)) revert ZeroAddress();
        if (value > type(uint192).max) value = type(uint192).max;
        if (value == 0) {
            expiresAt = 0;
        } else {
            if (expiresAt <= block.timestamp) revert ExpiryInPast(expiresAt);
            if (expiresAt - block.timestamp > MAX_APPROVAL_DURATION) {
                revert DurationTooLong(expiresAt - uint64(block.timestamp));
            }
        }
        _allowances[owner][spender] = Allowance(uint192(value), expiresAt);
        emit Approval(owner, spender, value);
        emit ApprovalExpiring(owner, spender, value, expiresAt);
    }

    function _transfer(address from, address to, uint256 value) internal {
        if (from == address(0) || to == address(0)) revert ZeroAddress();
        uint256 bal = balanceOf[from];
        if (bal < value) revert InsufficientBalance();
        unchecked {
            balanceOf[from] = bal - value;
            balanceOf[to] += value;
        }
        emit Transfer(from, to, value);
    }

    function _mint(address to, uint256 value) internal {
        if (to == address(0)) revert ZeroAddress();
        totalSupply += value;
        unchecked {
            balanceOf[to] += value;
        }
        emit Transfer(address(0), to, value);
    }

    function _buildDomainSeparator() private view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }
}
