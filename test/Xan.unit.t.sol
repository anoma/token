// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";

import {IXan, Xan} from "../src/Xan.sol";

contract UnitTest is Test {
    address internal _defaultSender;
    Xan internal _xanProxy;

    function setUp() public {
        (, _defaultSender,) = vm.readCallers();

        vm.prank(_defaultSender);
        _xanProxy = Xan(
            Upgrades.deployUUPSProxy({
                contractName: "Xan.sol:Xan",
                initializerData: abi.encodeCall(Xan.initialize, (_defaultSender))
            })
        );
    }

    function test_lock_emits_the_Locked_event() public {
        uint256 valueToLock = _xanProxy.unlockedBalanceOf(_defaultSender) / 2;

        vm.expectEmit(address(_xanProxy));
        emit IXan.Locked({owner: _defaultSender, value: valueToLock});

        vm.prank(_defaultSender);
        _xanProxy.lock(valueToLock);
    }

    function test_castVote_emits_the_VoteCast_event() public {
        uint256 valueToLock = _xanProxy.unlockedBalanceOf(_defaultSender) / 2;

        address impl = address(uint160(1));

        vm.startPrank(_defaultSender);
        _xanProxy.lock(valueToLock);

        vm.expectEmit(address(_xanProxy));
        emit IXan.VoteCast({voter: _defaultSender, implementation: impl, value: valueToLock});

        _xanProxy.castVote(impl);

        // TODO lock more
    }

    function test_revokeVote_emits_the_VoteRevoked_event() public {
        uint256 valueToLock = _xanProxy.unlockedBalanceOf(_defaultSender) / 2;

        address impl = address(uint160(1));

        vm.startPrank(_defaultSender);
        _xanProxy.lock(valueToLock);
        _xanProxy.castVote(impl);

        vm.expectEmit(address(_xanProxy));
        emit IXan.VoteRevoked({voter: _defaultSender, implementation: impl, value: valueToLock});
        _xanProxy.revokeVote(impl);

        vm.stopPrank();
    }

    function test_lockedBalanceOf_returns_the_locked_balance() public {
        uint256 valueToLock = _xanProxy.unlockedBalanceOf(_defaultSender) / 3;

        vm.prank(_defaultSender);
        _xanProxy.lock(valueToLock);

        assertEq(_xanProxy.lockedBalanceOf(_defaultSender), valueToLock);
    }

    function test_unlockedBalanceOf_returns_the_unlocked_balance() public {
        uint256 valueToLock = _xanProxy.unlockedBalanceOf(_defaultSender) / 3;
        uint256 expectedUnlocked = _xanProxy.unlockedBalanceOf(_defaultSender) - valueToLock;

        vm.prank(_defaultSender);
        _xanProxy.lock(valueToLock);

        assertEq(_xanProxy.unlockedBalanceOf(_defaultSender), expectedUnlocked);
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
