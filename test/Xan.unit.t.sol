// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Test} from "forge-std/Test.sol";

import {Parameters} from "../src/libs/Parameters.sol";
import {IXanV1, XanV1} from "../src/XanV1.sol";

contract UnitTest is Test {
    address internal _defaultSender;
    XanV1 internal _xanProxy;

    address internal constant _IMPL = address(uint160(1));

    function setUp() public {
        (, _defaultSender,) = vm.readCallers();

        vm.prank(_defaultSender);
        _xanProxy = XanV1(
            Upgrades.deployUUPSProxy({
                contractName: "XanV1.sol:XanV1",
                initializerData: abi.encodeCall(XanV1.initialize, _defaultSender)
            })
        );
    }

    function test_initialize_mints_the_supply_for_the_specified_owner() public {
        XanV1 uninitializedProxy =
            XanV1(Upgrades.deployUUPSProxy({contractName: "XanV1.sol:XanV1", initializerData: ""}));

        assertEq(uninitializedProxy.unlockedBalanceOf(_defaultSender), 0);

        uninitializedProxy.initialize({initialOwner: _defaultSender});

        assertEq(uninitializedProxy.unlockedBalanceOf(_defaultSender), Parameters.SUPPLY);
    }

    function test_lock_emits_the_Locked_event() public {
        uint256 valueToLock = _xanProxy.unlockedBalanceOf(_defaultSender) / 3;

        vm.expectEmit(address(_xanProxy));
        emit IXanV1.Locked({owner: _defaultSender, value: valueToLock});

        vm.prank(_defaultSender);
        _xanProxy.lock(valueToLock);
    }

    function test_castVote_emits_the_VoteCast_event() public {
        uint256 valueToLock = _xanProxy.unlockedBalanceOf(_defaultSender) / 3;

        vm.startPrank(_defaultSender);
        _xanProxy.lock(valueToLock);

        vm.expectEmit(address(_xanProxy));
        emit IXanV1.VoteCast({voter: _defaultSender, implementation: _IMPL, value: valueToLock});

        _xanProxy.castVote(_IMPL);
        vm.stopPrank();
    }

    function test_castVote_reverts_if_zero_tokens_have_been_locked() public {
        vm.prank(_defaultSender);

        vm.expectRevert(
            abi.encodeWithSelector(XanV1.InsufficientLockedBalance.selector, _defaultSender, 0), address(_xanProxy)
        );
        _xanProxy.castVote(_IMPL);
    }

    function test_castVote_ranks_an_implementation_on_first_vote() public {
        // Check that no implementation has rank 0.
        uint64 rank = 0;
        vm.expectRevert(
            abi.encodeWithSelector(XanV1.ImplementationRankNonExistent.selector, 0, rank), address(_xanProxy)
        );
        _xanProxy.implementationRank(rank);

        // Lock, vote, and check that there is an implementation with rank 0.
        vm.startPrank(_defaultSender);
        _xanProxy.lock(_xanProxy.unlockedBalanceOf(_defaultSender));
        _xanProxy.castVote(_IMPL);
        vm.stopPrank();
        assertEq(_IMPL, _xanProxy.implementationRank(rank));

        // Check that no implementation has rank 1.
        rank = 1;
        vm.expectRevert(
            abi.encodeWithSelector(XanV1.ImplementationRankNonExistent.selector, 1, rank), address(_xanProxy)
        );
        _xanProxy.implementationRank(rank);
    }

    function test_castVote_reverts_if_the_votum_has_already_been_casted() public {
        uint256 valueToLock = _xanProxy.unlockedBalanceOf(_defaultSender) / 3;

        vm.startPrank(_defaultSender);
        _xanProxy.lock(valueToLock);
        _xanProxy.castVote(_IMPL);

        vm.expectRevert(
            abi.encodeWithSelector(XanV1.InsufficientLockedBalance.selector, _defaultSender, valueToLock),
            address(_xanProxy)
        );
        _xanProxy.castVote(_IMPL);

        vm.stopPrank();
    }

    function test_castVote_increases_votes_if_more_tokens_have_been_locked() public {
        uint256 firstLockValue = _xanProxy.unlockedBalanceOf(_defaultSender) / 3;
        uint256 secondLockValue = _xanProxy.unlockedBalanceOf(_defaultSender) - firstLockValue;

        vm.startPrank(_defaultSender);

        _xanProxy.lock(firstLockValue);
        _xanProxy.castVote(_IMPL);
        assertEq(_xanProxy.totalVotes(_IMPL), firstLockValue);

        _xanProxy.lock(secondLockValue);
        _xanProxy.castVote(_IMPL);
        assertEq(_xanProxy.totalVotes(_IMPL), firstLockValue + secondLockValue);

        vm.stopPrank();
    }

    function test_revokeVote_emits_the_VoteRevoked_event() public {
        uint256 valueToLock = _xanProxy.unlockedBalanceOf(_defaultSender) / 2;

        vm.startPrank(_defaultSender);
        _xanProxy.lock(valueToLock);
        _xanProxy.castVote(_IMPL);

        vm.expectEmit(address(_xanProxy));
        emit IXanV1.VoteRevoked({voter: _defaultSender, implementation: _IMPL, value: valueToLock});

        _xanProxy.revokeVote(_IMPL);
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
        uint256 expectedUnlockedValue = _xanProxy.unlockedBalanceOf(_defaultSender) - valueToLock;

        vm.prank(_defaultSender);
        _xanProxy.lock(valueToLock);

        assertEq(expectedUnlockedValue, _xanProxy.unlockedBalanceOf(_defaultSender));
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
