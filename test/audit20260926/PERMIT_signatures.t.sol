// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ExpiringToken} from "../../src/ExpiringToken.sol";
import {ERC20Expiring} from "../../src/ERC20Expiring.sol";

contract Wallet1271 {
    address immutable signer;

    constructor(address s) {
        signer = s;
    }

    function isValidSignature(bytes32 hash, bytes memory sig) external view returns (bytes4) {
        bytes32 r;
        bytes32 s;
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
        }
        return ecrecover(hash, uint8(sig[64]), r, s) == signer ? this.isValidSignature.selector : bytes4(0xffffffff);
    }
}

contract PermitSignaturesTest is Test {
    ExpiringToken token;
    uint256 key = 0xB0B;
    address holder;
    address spender = makeAddr("spender");

    function setUp() public {
        vm.warp(1_700_000_000);
        holder = vm.addr(key);
        token = new ExpiringToken("E", "E", holder, 100e18);
    }

    function _sign2612(address owner, uint256 value, uint256 deadline) internal view returns (uint8, bytes32, bytes32) {
        bytes32 sh =
            keccak256(abi.encode(token.PERMIT_TYPEHASH(), owner, spender, value, token.nonces(owner), deadline));
        return vm.sign(key, keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), sh)));
    }

    function test_PERMIT1_regression_eip2612PermitUsesOwnerDefault() public {
        vm.prank(holder);
        token.setDefaultApprovalDuration(2 hours);
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _sign2612(holder, 3e18, deadline);
        token.permit(holder, spender, 3e18, deadline, v, r, s);
        (uint256 val, uint64 exp) = token.allowanceWithExpiry(holder, spender);
        assertEq(val, 3e18);
        assertEq(exp, block.timestamp + 2 hours);
    }

    function test_PERMIT1_regression_eip2612MaxValueClamps() public {
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _sign2612(holder, type(uint256).max, deadline);
        token.permit(holder, spender, type(uint256).max, deadline, v, r, s);
        assertEq(token.allowance(holder, spender), type(uint192).max);
    }

    function test_PERMIT3_regression_expiringSigNotAcceptedAs2612() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint64 exp = uint64(block.timestamp + 1 days);
        bytes32 sh = keccak256(
            abi.encode(token.EXPIRING_PERMIT_TYPEHASH(), holder, spender, 1e18, exp, token.nonces(holder), deadline)
        );
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(key, keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), sh)));
        vm.expectRevert(ERC20Expiring.InvalidSignature.selector);
        token.permit(holder, spender, 1e18, deadline, v, r, s);
        token.permit(holder, spender, 1e18, exp, deadline, v, r, s);
        assertEq(token.allowance(holder, spender), 1e18);
    }

    function test_PERMIT4_regression_contractWalletPermit() public {
        Wallet1271 wallet = new Wallet1271(holder);
        vm.prank(holder);
        token.transfer(address(wallet), 10e18);
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _sign2612(address(wallet), 5e18, deadline);
        token.permit(address(wallet), spender, 5e18, deadline, v, r, s);
        assertEq(token.allowance(address(wallet), spender), 5e18);
    }

    function test_PERMIT4_regression_contractWalletRejectsForeignSig() public {
        Wallet1271 wallet = new Wallet1271(makeAddr("other"));
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _sign2612(address(wallet), 5e18, deadline);
        vm.expectRevert(ERC20Expiring.InvalidSignature.selector);
        token.permit(address(wallet), spender, 5e18, deadline, v, r, s);
    }

    function test_PERMIT4_regression_delegatedEoaStillVerifiesByKey() public {
        vm.etch(holder, hex"ef0100deadbeefdeadbeefdeadbeefdeadbeefdeadbeef");
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _sign2612(holder, 1e18, deadline);
        token.permit(holder, spender, 1e18, deadline, v, r, s);
        assertEq(token.allowance(holder, spender), 1e18);
    }

    function test_highSRejected() public {
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _sign2612(holder, 1e18, deadline);
        uint256 n = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
        vm.expectRevert(ERC20Expiring.InvalidSignature.selector);
        token.permit(holder, spender, 1e18, deadline, v == 27 ? 28 : 27, r, bytes32(n - uint256(s)));
    }

    function test_expiredDeadlineRejected() public {
        uint256 deadline = block.timestamp - 1;
        (uint8 v, bytes32 r, bytes32 s) = _sign2612(holder, 1e18, deadline);
        vm.expectRevert(ERC20Expiring.PermitExpired.selector);
        token.permit(holder, spender, 1e18, deadline, v, r, s);
    }
}

contract ReturnBomb {
    fallback() external {
        assembly {
            mstore(0, 0x1626ba7e00000000000000000000000000000000000000000000000000000000)
            return(0, 1000000)
        }
    }
}

contract REVIEW2 is Test {
    function test_REVIEW2_regression_returnBombCostsBounded() public {
        ExpiringToken token = new ExpiringToken("E", "E", address(this), 1);
        ReturnBomb bomb = new ReturnBomb();
        uint256 g = gasleft();
        token.permit(address(bomb), address(this), 1, block.timestamp, 27, bytes32(uint256(1)), bytes32(uint256(1)));
        assertLt(g - gasleft(), 3_000_000, "caller copied the full return data");
    }
}
