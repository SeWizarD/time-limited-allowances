// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ExpiringToken} from "../src/ExpiringToken.sol";
import {ERC20Expiring} from "../src/ERC20Expiring.sol";
import {IERC20Expiring} from "../src/interfaces/IERC20Expiring.sol";

contract ExpiringTokenTest is Test {
    ExpiringToken token;
    uint256 ownerKey = 0xA11CE;
    address owner;
    address spender = makeAddr("spender");
    address bob = makeAddr("bob");

    function setUp() public {
        vm.warp(1_700_000_000);
        owner = vm.addr(ownerKey);
        token = new ExpiringToken("Expiring", "EXP", owner, 1_000e18);
    }

    function test_approveWithExpiry_spendableUntilExpiry() public {
        uint64 exp = uint64(block.timestamp + 1 hours);
        vm.prank(owner);
        token.approve(spender, 100e18, exp);

        vm.warp(exp - 1);
        vm.prank(spender);
        token.transferFrom(owner, bob, 40e18);
        assertEq(token.allowance(owner, spender), 60e18);

        vm.warp(exp);
        assertEq(token.allowance(owner, spender), 0);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Expiring.ApprovalExpired.selector, owner, spender, exp));
        token.transferFrom(owner, bob, 1);
    }

    function test_plainApprove_usesOwnerDefault() public {
        vm.prank(owner);
        assertTrue(token.approve(spender, 5e18));
        (uint256 v, uint64 exp) = token.allowanceWithExpiry(owner, spender);
        assertEq(v, 5e18);
        assertEq(exp, block.timestamp + 1 days);

        vm.startPrank(owner);
        token.setDefaultApprovalDuration(10 minutes);
        token.approve(spender, 5e18);
        vm.expectRevert(abi.encodeWithSelector(IERC20Expiring.DurationTooLong.selector, uint64(366 days)));
        token.setDefaultApprovalDuration(366 days);
        vm.stopPrank();
        (, exp) = token.allowanceWithExpiry(owner, spender);
        assertEq(exp, block.timestamp + 10 minutes);

        vm.warp(exp);
        assertEq(token.allowance(owner, spender), 0);
    }

    function test_rejectsPastAndTooLongExpiry() public {
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(IERC20Expiring.ExpiryInPast.selector, uint64(block.timestamp)));
        token.approve(spender, 1, uint64(block.timestamp));
        vm.expectRevert();
        token.approve(spender, 1, uint64(block.timestamp + 366 days));
        vm.stopPrank();
    }

    function test_revokeWithZero_ignoresExpiry() public {
        vm.startPrank(owner);
        token.approve(spender, 1e18, uint64(block.timestamp + 1 hours));
        token.approve(spender, 0, 0);
        vm.stopPrank();
        assertEq(token.allowance(owner, spender), 0);
    }

    function test_permit() public {
        uint64 exp = uint64(block.timestamp + 2 hours);
        uint256 deadline = block.timestamp + 10 minutes;
        bytes32 structHash = keccak256(
            abi.encode(token.EXPIRING_PERMIT_TYPEHASH(), owner, spender, 7e18, exp, token.nonces(owner), deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, digest);

        token.permit(owner, spender, 7e18, exp, deadline, v, r, s);
        (uint256 val, uint64 got) = token.allowanceWithExpiry(owner, spender);
        assertEq(val, 7e18);
        assertEq(got, exp);
        assertEq(token.nonces(owner), 1);

        vm.expectRevert(ERC20Expiring.InvalidSignature.selector);
        token.permit(owner, spender, 7e18, exp, deadline, v, r, s);
    }

    function testFuzz_allowanceZeroAfterExpiry(uint96 amount, uint32 ttl, uint32 later) public {
        vm.assume(amount > 0);
        ttl = uint32(bound(ttl, 1, 365 days));
        uint64 exp = uint64(block.timestamp) + ttl;
        vm.prank(owner);
        token.approve(spender, amount, exp);
        vm.warp(uint256(exp) + later);
        assertEq(token.allowance(owner, spender), 0);
    }
}
