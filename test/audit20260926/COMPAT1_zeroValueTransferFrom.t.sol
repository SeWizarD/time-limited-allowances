// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ExpiringToken} from "../../src/ExpiringToken.sol";
import {IERC20Expiring} from "../../src/interfaces/IERC20Expiring.sol";

contract COMPAT1 is Test {
    ExpiringToken token;
    address holder = makeAddr("holder");
    address spender = makeAddr("spender");

    function setUp() public {
        token = new ExpiringToken("E", "E", holder, 100e18);
    }

    function test_COMPAT1_regression_zeroTransferFromSucceeds() public {
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, spender, 0));
        assertEq(token.balanceOf(holder), 100e18);
    }

    function test_COMPAT1_regression_nonZeroStillNeedsLiveAllowance() public {
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Expiring.ApprovalExpired.selector, holder, spender, uint64(0)));
        token.transferFrom(holder, spender, 1);
    }
}

contract INFO1 is Test {
    function test_INFO1_regression_revokeStoresZeroExpiry() public {
        address holder = makeAddr("holder");
        address spender = makeAddr("spender");
        ExpiringToken token = new ExpiringToken("E", "E", holder, 1);
        vm.startPrank(holder);
        token.approve(spender, 1, uint64(block.timestamp + 1 hours));
        token.approve(spender, 0, type(uint64).max);
        vm.stopPrank();
        (uint256 v, uint64 exp) = token.allowanceWithExpiry(holder, spender);
        assertEq(v, 0);
        assertEq(exp, 0);
    }
}

contract REVIEW1 is Test {
    function test_REVIEW1_regression_noFakeMintEvent() public {
        ExpiringToken token = new ExpiringToken("E", "E", address(this), 1);
        vm.expectRevert();
        token.transferFrom(address(0), address(this), 0);
    }
}
