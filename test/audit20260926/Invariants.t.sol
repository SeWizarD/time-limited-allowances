// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ExpiringToken} from "../../src/ExpiringToken.sol";

contract Handler is Test {
    ExpiringToken public token;
    address[] public actors;
    mapping(address => mapping(address => uint256)) public setAt;
    uint256 public spentPastExpiry;
    uint256 public spentOverApproval;
    uint256 public cancelledPermitUsed;
    mapping(address => uint256) public keys;
    mapping(address => bool) public cancelNext;

    constructor(ExpiringToken t, address[] memory a) {
        token = t;
        actors = a;
        for (uint256 i; i < a.length; i++) {
            keys[a[i]] = i + 1;
        }
    }

    function _pick(uint256 i) internal view returns (address) {
        return actors[i % actors.length];
    }

    function transfer(uint256 f, uint256 t, uint256 amt) external {
        address from = _pick(f);
        amt = bound(amt, 0, token.balanceOf(from));
        vm.prank(from);
        token.transfer(_pick(t), amt);
    }

    function approveFor(uint256 o, uint256 s, uint256 amt, uint256 ttl) external {
        address owner = _pick(o);
        address spender = _pick(s);
        ttl = bound(ttl, 1, 365 days);
        vm.prank(owner);
        token.approve(spender, bound(amt, 0, 1e30), uint64(block.timestamp + ttl));
        setAt[owner][spender] = block.timestamp;
    }

    function approvePlain(uint256 o, uint256 s, uint256 amt) external {
        address owner = _pick(o);
        address spender = _pick(s);
        vm.prank(owner);
        token.approve(spender, bound(amt, 0, 1e30));
        setAt[owner][spender] = block.timestamp;
    }

    function setDefault(uint256 o, uint64 d) external {
        vm.prank(_pick(o));
        token.setDefaultApprovalDuration(uint64(bound(d, 0, 365 days)));
    }

    function spend(uint256 o, uint256 s, uint256 t, uint256 amt) external {
        address owner = _pick(o);
        address spender = _pick(s);
        (uint256 allowed, uint64 exp) = token.allowanceWithExpiry(owner, spender);
        amt = bound(amt, 1, 1e30);
        vm.prank(spender);
        try token.transferFrom(owner, _pick(t), amt) {
            if (block.timestamp >= exp) spentPastExpiry++;
            if (amt > allowed) spentOverApproval++;
        } catch {}
    }

    function permitExpiring(uint256 o, uint256 s, uint256 amt, uint256 ttl) external {
        address owner = _pick(o);
        address spender = _pick(s);
        amt = bound(amt, 0, 1e30);
        uint64 exp = uint64(block.timestamp + bound(ttl, 1, 365 days));
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 sh = keccak256(
            abi.encode(token.EXPIRING_PERMIT_TYPEHASH(), owner, spender, amt, exp, token.nonces(owner), deadline)
        );
        (uint8 v, bytes32 r, bytes32 sg) =
            vm.sign(keys[owner], keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), sh)));
        if (cancelNext[owner]) {
            cancelNext[owner] = false;
            vm.prank(owner);
            token.invalidateNonce();
            try token.permit(owner, spender, amt, exp, deadline, v, r, sg) {
                cancelledPermitUsed++;
            } catch {}
            return;
        }
        token.permit(owner, spender, amt, exp, deadline, v, r, sg);
        setAt[owner][spender] = block.timestamp;
    }

    function permit2612(uint256 o, uint256 s, uint256 amt) external {
        address owner = _pick(o);
        address spender = _pick(s);
        amt = bound(amt, 0, 1e30);
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 sh = keccak256(abi.encode(token.PERMIT_TYPEHASH(), owner, spender, amt, token.nonces(owner), deadline));
        (uint8 v, bytes32 r, bytes32 sg) =
            vm.sign(keys[owner], keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), sh)));
        token.permit(owner, spender, amt, deadline, v, r, sg);
        setAt[owner][spender] = block.timestamp;
    }

    function armCancel(uint256 o) external {
        cancelNext[_pick(o)] = true;
    }

    function warp(uint256 dt) external {
        vm.warp(block.timestamp + bound(dt, 0, 30 days));
    }
}

contract InvariantsTest is Test {
    ExpiringToken token;
    Handler handler;
    address[] actors;

    function setUp() public {
        for (uint256 i; i < 4; i++) {
            actors.push(vm.addr(i + 1));
        }
        token = new ExpiringToken("E", "E", actors[0], 1e24);
        vm.prank(actors[0]);
        token.transfer(actors[1], 3e23);
        handler = new Handler(token, actors);
        targetContract(address(handler));
    }

    function invariant_supplyConserved() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; i++) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(sum, token.totalSupply());
    }

    function invariant_noSpendPastExpiryOrOverAllowance() public view {
        assertEq(handler.spentPastExpiry(), 0);
        assertEq(handler.spentOverApproval(), 0);
        assertEq(handler.cancelledPermitUsed(), 0);
    }

    function invariant_allowancesBounded() public view {
        for (uint256 i; i < actors.length; i++) {
            for (uint256 j; j < actors.length; j++) {
                (uint256 v, uint64 exp) = token.allowanceWithExpiry(actors[i], actors[j]);
                if (v > 0) {
                    assertLt(block.timestamp, exp);
                    assertLe(exp - handler.setAt(actors[i], actors[j]), 365 days);
                }
            }
        }
    }

    function invariant_defaultInRange() public view {
        for (uint256 i; i < actors.length; i++) {
            uint64 d = token.defaultApprovalDuration(actors[i]);
            assertGt(d, 0);
            assertLe(d, 365 days);
        }
    }
}
