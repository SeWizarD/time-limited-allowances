// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ExpiringToken} from "../../src/ExpiringToken.sol";

contract APPROVE1 is Test {
    ExpiringToken token;
    address holder = makeAddr("holder");
    address router = makeAddr("router");

    function setUp() public {
        token = new ExpiringToken("E", "E", holder, 100e18);
    }

    function test_APPROVE1_regression_maxUintApproveClampsAndExpires() public {
        vm.prank(holder);
        assertTrue(token.approve(router, type(uint256).max));
        assertEq(token.allowance(holder, router), type(uint192).max);

        vm.prank(router);
        token.transferFrom(holder, router, 10e18);
        assertEq(token.allowance(holder, router), type(uint192).max - 10e18);

        vm.warp(block.timestamp + 1 days);
        assertEq(token.allowance(holder, router), 0);
    }
}
