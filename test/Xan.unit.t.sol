// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";

import {Test} from "forge-std/Test.sol";

import {Parameters} from "../src/libs/Parameters.sol";
import {IXanV1, XanV1} from "../src/XanV1.sol";

contract UnitTest is Test {
    address internal _defaultSender;
    XanV1 internal _xanProxy;

    address internal constant _IMPL = address(uint160(1));
    address internal constant _OTHER_IMPL = address(uint160(2));
    address internal constant _RECEIVER = address(uint160(3));

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

    function test_lock_locks_incrementally() public {
        vm.startPrank(_defaultSender);
        assertEq(_xanProxy.lockedBalanceOf(_defaultSender), 0);
        _xanProxy.lock(1);
        assertEq(_xanProxy.lockedBalanceOf(_defaultSender), 1);
        _xanProxy.lock(1);
        assertEq(_xanProxy.lockedBalanceOf(_defaultSender), 2);
        vm.stopPrank();
    }

    function test_lock_emits_the_Locked_event() public {
        uint256 valueToLock = Parameters.SUPPLY / 3;

        vm.expectEmit(address(_xanProxy));
        emit IXanV1.Locked({account: _defaultSender, value: valueToLock});

        vm.prank(_defaultSender);
        _xanProxy.lock(valueToLock);
    }

    function test_transfer_reverts_on_insufficient_unlocked_tokens() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.SUPPLY);

        uint256 unlocked = _xanProxy.unlockedBalanceOf(_defaultSender);
        assertEq(unlocked, 0);

        uint256 toTransfer = 1;

        vm.expectRevert(
            abi.encodeWithSelector(XanV1.UnlockedBalanceInsufficient.selector, _defaultSender, unlocked, toTransfer),
            address(_xanProxy)
        );
        _xanProxy.transfer({to: _RECEIVER, value: 1});
    }

    function test_transfer_transfers_tokens() public {
        assertEq(_xanProxy.balanceOf(_defaultSender), Parameters.SUPPLY);
        assertEq(_xanProxy.unlockedBalanceOf(_defaultSender), Parameters.SUPPLY);
        assertEq(_xanProxy.lockedBalanceOf(_defaultSender), 0);

        assertEq(_xanProxy.balanceOf(_RECEIVER), 0);
        assertEq(_xanProxy.unlockedBalanceOf(_RECEIVER), 0);
        assertEq(_xanProxy.lockedBalanceOf(_RECEIVER), 0);

        vm.prank(_defaultSender);
        _xanProxy.transfer({to: _RECEIVER, value: 1});

        assertEq(_xanProxy.balanceOf(_defaultSender), Parameters.SUPPLY - 1);
        assertEq(_xanProxy.unlockedBalanceOf(_defaultSender), Parameters.SUPPLY - 1);
        assertEq(_xanProxy.lockedBalanceOf(_defaultSender), 0);

        assertEq(_xanProxy.balanceOf(_RECEIVER), 1);
        assertEq(_xanProxy.unlockedBalanceOf(_RECEIVER), 1);
        assertEq(_xanProxy.lockedBalanceOf(_RECEIVER), 0);
    }

    function test_transfer_emits_the_Transfer_event() public {
        vm.expectEmit(address(_xanProxy));
        emit IERC20.Transfer({from: _defaultSender, to: _RECEIVER, value: 1});

        vm.prank(_defaultSender);
        _xanProxy.transfer({to: _RECEIVER, value: 1});
    }

    function test_transferAndLock_reverts_on_insufficient_unlocked_tokens() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.SUPPLY);

        uint256 unlocked = _xanProxy.unlockedBalanceOf(_defaultSender);
        assertEq(unlocked, 0);

        uint256 toTransfer = 1;

        vm.expectRevert(
            abi.encodeWithSelector(XanV1.UnlockedBalanceInsufficient.selector, _defaultSender, unlocked, toTransfer),
            address(_xanProxy)
        );
        _xanProxy.transferAndLock({to: _RECEIVER, value: 1});
    }

    function test_transfer_transfers_and_locks_tokens() public {
        assertEq(_xanProxy.balanceOf(_defaultSender), Parameters.SUPPLY);
        assertEq(_xanProxy.unlockedBalanceOf(_defaultSender), Parameters.SUPPLY);
        assertEq(_xanProxy.lockedBalanceOf(_defaultSender), 0);

        assertEq(_xanProxy.balanceOf(_RECEIVER), 0);
        assertEq(_xanProxy.unlockedBalanceOf(_RECEIVER), 0);
        assertEq(_xanProxy.lockedBalanceOf(_RECEIVER), 0);

        vm.prank(_defaultSender);
        _xanProxy.transferAndLock({to: _RECEIVER, value: 1});

        assertEq(_xanProxy.balanceOf(_defaultSender), Parameters.SUPPLY - 1);
        assertEq(_xanProxy.unlockedBalanceOf(_defaultSender), Parameters.SUPPLY - 1);
        assertEq(_xanProxy.lockedBalanceOf(_defaultSender), 0);

        assertEq(_xanProxy.balanceOf(_RECEIVER), 1);
        assertEq(_xanProxy.unlockedBalanceOf(_RECEIVER), 0);
        assertEq(_xanProxy.lockedBalanceOf(_RECEIVER), 1);
    }

    function test_burn_reverts_on_insufficient_unlocked_tokens() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(_xanProxy.balanceOf(_defaultSender));

        vm.expectRevert(
            abi.encodeWithSelector(XanV1.UnlockedBalanceInsufficient.selector, _defaultSender, 0, 1), address(_xanProxy)
        );
        _xanProxy.burn(1);
        vm.stopPrank();
    }

    function test_burn_burns_unlocked_tokens() public {
        uint256 balance = _xanProxy.balanceOf(_defaultSender);
        assertEq(balance, _xanProxy.totalSupply());

        vm.startPrank(_defaultSender);
        _xanProxy.burn(balance);
        vm.stopPrank();

        assertEq(_xanProxy.totalSupply(), 0);
    }

    function test_castVote_emits_the_VoteCast_event() public {
        uint256 valueToLock = Parameters.SUPPLY / 3;

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
            abi.encodeWithSelector(XanV1.LockedBalanceInsufficient.selector, _defaultSender, 0), address(_xanProxy)
        );
        _xanProxy.castVote(_IMPL);
    }

    function test_castVote_ranks_an_implementation_on_first_vote() public {
        // Check that no implementation has rank 0.
        uint48 rank = 0;
        vm.expectRevert(
            abi.encodeWithSelector(XanV1.ImplementationRankNonExistent.selector, 0, rank), address(_xanProxy)
        );
        _xanProxy.proposedImplementationByRank(rank);

        // Lock, vote, and check that there is an implementation with rank 0.
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.SUPPLY);
        _xanProxy.castVote(_IMPL);
        vm.stopPrank();
        assertEq(_IMPL, _xanProxy.proposedImplementationByRank(rank));

        // Check that no implementation has rank 1.
        rank = 1;
        vm.expectRevert(
            abi.encodeWithSelector(XanV1.ImplementationRankNonExistent.selector, 1, rank), address(_xanProxy)
        );
        _xanProxy.proposedImplementationByRank(rank);
    }

    function test_castVote_reverts_if_the_votum_has_already_been_casted() public {
        uint256 valueToLock = Parameters.SUPPLY / 3;

        vm.startPrank(_defaultSender);
        _xanProxy.lock(valueToLock);
        _xanProxy.castVote(_IMPL);

        vm.expectRevert(
            abi.encodeWithSelector(XanV1.LockedBalanceInsufficient.selector, _defaultSender, valueToLock),
            address(_xanProxy)
        );
        _xanProxy.castVote(_IMPL);

        vm.stopPrank();
    }

    function test_castVote_reverts_if_caller_has_no_locked_tokens() public {
        vm.prank(_defaultSender);
        vm.expectRevert(
            abi.encodeWithSelector(XanV1.LockedBalanceInsufficient.selector, _defaultSender, 0), address(_xanProxy)
        );
        _xanProxy.castVote(_IMPL);
    }

    function test_castVote_increases_votes_if_more_tokens_have_been_locked() public {
        uint256 firstLockValue = Parameters.SUPPLY / 3;
        uint256 secondLockValue = Parameters.SUPPLY - firstLockValue;

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
        uint256 valueToLock = Parameters.SUPPLY / 2;

        vm.startPrank(_defaultSender);
        _xanProxy.lock(valueToLock);
        _xanProxy.castVote(_IMPL);

        vm.expectEmit(address(_xanProxy));
        emit IXanV1.VoteRevoked({voter: _defaultSender, implementation: _IMPL, value: valueToLock});

        _xanProxy.revokeVote(_IMPL);
        vm.stopPrank();
    }

    function test_startUpgradeDelay_starts_the_delay_if_quorum_is_met_and_the_implementation_is_ranked_best() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.SUPPLY);
        _xanProxy.castVote(_IMPL);
        vm.stopPrank();

        assertGt(_xanProxy.totalVotes(_IMPL), _xanProxy.calculateQuorum());
        assertEq(_xanProxy.proposedImplementationByRank(0), _IMPL);

        uint48 currentTime = Time.timestamp();
        _xanProxy.startUpgradeDelay(_IMPL);

        assertEq(_xanProxy.delayEndTime(), currentTime + Parameters.DELAY_DURATION);
        assertEq(_xanProxy.delayedUpgradeImplementation(), _IMPL);
    }

    function test_startUpgradeDelay_emits_the_DelayStarted_event() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.SUPPLY);
        _xanProxy.castVote(_IMPL);
        vm.stopPrank();

        uint48 currentTime = Time.timestamp();
        vm.expectEmit(address(_xanProxy));
        emit IXanV1.DelayStarted({
            implementation: _IMPL,
            startTime: currentTime,
            endTime: currentTime + Parameters.DELAY_DURATION
        });
        _xanProxy.startUpgradeDelay(_IMPL);
    }

    function test_startUpgradeDelay_reverts_if_quorum_is_not_met() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(_xanProxy.calculateQuorum());
        _xanProxy.castVote(_IMPL);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(XanV1.QuorumNotReached.selector, _IMPL), address(_xanProxy));
        _xanProxy.startUpgradeDelay(_IMPL);
    }

    function test_startUpgradeDelay_reverts_if_delay_has_already_been_started() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.SUPPLY);
        _xanProxy.castVote(_IMPL);
        vm.stopPrank();

        // Start the delay
        _xanProxy.startUpgradeDelay(_IMPL);

        // Try to start the delay again.
        vm.expectRevert(abi.encodeWithSelector(XanV1.DelayPeriodAlreadyStarted.selector, _IMPL), address(_xanProxy));
        _xanProxy.startUpgradeDelay(_IMPL);
    }

    function test_startUpgradeDelay_reverts_is_not_ranked_best() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(_xanProxy.calculateQuorum() + 1);
        _xanProxy.castVote(_IMPL);
        _xanProxy.castVote(_OTHER_IMPL);
        vm.stopPrank();

        assertEq(_xanProxy.proposedImplementationByRank(0), _IMPL);
        assertEq(_xanProxy.proposedImplementationByRank(1), _OTHER_IMPL);

        vm.expectRevert(
            abi.encodeWithSelector(XanV1.ImplementationNotRankedBest.selector, _IMPL, _OTHER_IMPL), address(_xanProxy)
        );
        _xanProxy.startUpgradeDelay(_OTHER_IMPL);
    }

    function test_resetUpgradeDelay_reverts_on_winning_implementation() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.SUPPLY - 1);
        _xanProxy.castVote(_IMPL);
        vm.stopPrank();

        _xanProxy.startUpgradeDelay(_IMPL);

        // Skip the delay period.
        skip(Parameters.DELAY_DURATION);

        vm.expectRevert(abi.encodeWithSelector(XanV1.UpgradeDelayNotResettable.selector, _IMPL), address(_xanProxy));
        _xanProxy.resetUpgradeDelay(_IMPL);
    }

    function test_resetUpgradeDelay_emits_the_DelayReset_event() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.SUPPLY - 1);
        _xanProxy.castVote(_IMPL);
        _xanProxy.startUpgradeDelay(_IMPL);

        // Vote with more weight for another implementation
        _xanProxy.lock(1);
        _xanProxy.castVote(_OTHER_IMPL);
        vm.stopPrank();

        assertEq(_xanProxy.proposedImplementationByRank(0), _OTHER_IMPL);
        assertEq(_xanProxy.proposedImplementationByRank(1), _IMPL);

        // Advance to the end of the delay period.
        skip(Parameters.DELAY_DURATION);

        // Reset the delay
        vm.expectEmit(address(_xanProxy));
        emit IXanV1.DelayReset({implementation: _IMPL});
        _xanProxy.resetUpgradeDelay(_IMPL);
    }

    function test_resetUpgradeDelay_resets_the_delay() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.SUPPLY - 1);
        _xanProxy.castVote(_IMPL);
        _xanProxy.startUpgradeDelay(_IMPL);

        uint48 currentTime = Time.timestamp();

        assertEq(_xanProxy.delayEndTime(), currentTime + Parameters.DELAY_DURATION);
        assertEq(_xanProxy.delayedUpgradeImplementation(), _IMPL);

        // Vote with more weight for another implementation
        _xanProxy.lock(1);
        _xanProxy.castVote(_OTHER_IMPL);
        vm.stopPrank();

        assertEq(_xanProxy.proposedImplementationByRank(0), _OTHER_IMPL);
        assertEq(_xanProxy.proposedImplementationByRank(1), _IMPL);

        // Advance to the end of the delay period.
        skip(Parameters.DELAY_DURATION);

        // Reset the delay
        _xanProxy.resetUpgradeDelay(_IMPL);

        // Check state change has happened
        assertEq(_xanProxy.delayEndTime(), 0);
        assertEq(_xanProxy.delayedUpgradeImplementation(), address(0));
    }

    function test_upgradeToAndCall_reverts_if_implementation_has_not_been_voted_on() public {
        vm.expectRevert(abi.encodeWithSelector(XanV1.DelayPeriodNotStarted.selector), address(_xanProxy));
        _xanProxy.upgradeToAndCall({newImplementation: _IMPL, data: ""});
    }

    function test_upgradeToAndCall_reverts_if_delay_period_has_not_started() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(_xanProxy.calculateQuorum() + 1);
        _xanProxy.castVote(_IMPL);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(XanV1.DelayPeriodNotStarted.selector), address(_xanProxy));
        _xanProxy.upgradeToAndCall({newImplementation: _IMPL, data: ""});
    }

    function test_upgradeToAndCall_reverts_if_delay_period_has_not_ended() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(_xanProxy.calculateQuorum() + 1);
        _xanProxy.castVote(_IMPL);
        vm.stopPrank();

        _xanProxy.startUpgradeDelay(_IMPL);

        vm.expectRevert(abi.encodeWithSelector(XanV1.DelayPeriodNotEnded.selector), address(_xanProxy));
        _xanProxy.upgradeToAndCall({newImplementation: _IMPL, data: ""});
    }

    function test_upgradeToAndCall_reverts_if_quorum_is_not_met() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(_xanProxy.calculateQuorum() + 1);
        _xanProxy.castVote(_IMPL);
        vm.stopPrank();

        _xanProxy.startUpgradeDelay(_IMPL);
        skip(Parameters.DELAY_DURATION);

        vm.prank(_defaultSender);
        _xanProxy.revokeVote(_IMPL);

        vm.expectRevert(abi.encodeWithSelector(XanV1.QuorumNotReached.selector, _IMPL), address(_xanProxy));
        _xanProxy.upgradeToAndCall({newImplementation: _IMPL, data: ""});
    }

    function test_upgradeToAndCall_reverts_if_implementation_is_not_best_ranked() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(_xanProxy.calculateQuorum() + 1);
        _xanProxy.castVote(_IMPL);
        assertEq(_xanProxy.proposedImplementationByRank(0), _IMPL);

        _xanProxy.startUpgradeDelay(_IMPL);
        _xanProxy.lock(1);
        _xanProxy.castVote(_OTHER_IMPL);
        vm.stopPrank();

        assertEq(_xanProxy.proposedImplementationByRank(0), _OTHER_IMPL); // Delay has not started
        assertEq(_xanProxy.proposedImplementationByRank(1), _IMPL); // Delay has started

        skip(Parameters.DELAY_DURATION);

        vm.expectRevert(
            abi.encodeWithSelector(XanV1.ImplementationNotRankedBest.selector, _OTHER_IMPL, _IMPL), address(_xanProxy)
        );
        _xanProxy.upgradeToAndCall({newImplementation: _IMPL, data: ""});
    }

    function test_lockedBalanceOf_returns_the_locked_balance() public {
        uint256 valueToLock = Parameters.SUPPLY / 3;

        vm.prank(_defaultSender);
        _xanProxy.lock(valueToLock);

        assertEq(_xanProxy.lockedBalanceOf(_defaultSender), valueToLock);
    }

    function test_unlockedBalanceOf_returns_the_unlocked_balance() public {
        uint256 valueToLock = Parameters.SUPPLY / 3;
        uint256 expectedUnlockedValue = Parameters.SUPPLY - valueToLock;

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
