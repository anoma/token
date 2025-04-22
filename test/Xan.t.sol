// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";

import {IXan, Xan} from "../src/Xan.sol";

contract XanTest is Test {
    address internal _defaultSender;
    Xan internal _xanProxy;

    function setUp() public {
        (, _defaultSender,) = vm.readCallers();

        _xanProxy = Xan(
            Upgrades.deployUUPSProxy({contractName: "Xan.sol:Xan", initializerData: abi.encodeCall(Xan.initialize, ())})
        );
    }

    function test_lock_emits_the_locked_event() public {
        uint256 valueToLock = _xanProxy.unlockedBalanceOf(_defaultSender) / 2;

        vm.expectEmit(address(_xanProxy));
        emit IXan.Locked({owner: _defaultSender, value: valueToLock});

        vm.prank(_defaultSender);
        _xanProxy.lock(valueToLock);
    }

    function testFuzz_lockedBalanceOf_and_unlockedBalanceOf_sum_to_balanceOf(address owner) public view {
        assertEq(_xanProxy.lockedBalanceOf(owner) + _xanProxy.unlockedBalanceOf(owner), _xanProxy.balanceOf(owner));
    }

    function test_lockedBalanceOf_is_bound_by_balanceOf(address owner) public view {
        assertLe(_xanProxy.lockedBalanceOf(owner), _xanProxy.balanceOf(owner));
    }

    function test_unlockedBalanceOf_is_bound_by_balanceOf(address owner) public view {
        assertLe(_xanProxy.unlockedBalanceOf(owner), _xanProxy.balanceOf(owner));
    }

    function invariant_lockedBalance() public view {
        assertLe(_xanProxy.lockedTotalSupply(), _xanProxy.totalSupply());
    }
}
