// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ExpiringToken} from "../../src/ExpiringToken.sol";

contract PERMIT2 is Test {
    ExpiringToken token;
    uint256 key = 0xA11CE;
    address holder;
    address spender = makeAddr("spender");

    function setUp() public {
        holder = vm.addr(key);
        token = new ExpiringToken("E", "E", holder, 100e18);
    }

    function test_PERMIT2_regression_invalidateNonceKillsSignedPermit() public {
        uint64 exp = uint64(block.timestamp + 30 days);
        uint256 deadline = block.timestamp + 1 days;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                token.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        token.EXPIRING_PERMIT_TYPEHASH(), holder, spender, 50e18, exp, token.nonces(holder), deadline
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);

        vm.startPrank(holder);
        token.approve(spender, 0);
        token.invalidateNonce();
        vm.stopPrank();

        vm.expectRevert();
        token.permit(holder, spender, 50e18, exp, deadline, v, r, s);
        assertEq(token.allowance(holder, spender), 0);
    }
}
