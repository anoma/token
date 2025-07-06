// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {Upgrades, UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";

import {Test} from "forge-std/Test.sol";

import {Parameters} from "../src/libs/Parameters.sol";
import {IXanV1, XanV1} from "../src/XanV1.sol";

contract XanV1VotingTest is Test {
    address internal constant _NEW_IMPL = address(uint160(1));
    address internal constant _OTHER_NEW_IMPL = address(uint160(2));
    address internal constant _RECEIVER = address(uint160(3));
    address internal constant _COUNCIL = address(uint160(4));

    address internal _defaultSender;
    XanV1 internal _xanProxy;

    function setUp() public {
        (, _defaultSender,) = vm.readCallers();

        _xanProxy = XanV1(
            Upgrades.deployUUPSProxy({
                contractName: "XanV1.sol:XanV1",
                initializerData: abi.encodeCall(XanV1.initializeV1, (_defaultSender, _COUNCIL))
            })
        );
    }

    function test_castVote_emits_the_VoteCast_event() public {
        uint256 valueToLock = _xanProxy.totalSupply() / 3;

        vm.startPrank(_defaultSender);
        _xanProxy.lock(valueToLock);

        vm.expectEmit(address(_xanProxy));
        emit IXanV1.VoteCast({voter: _defaultSender, implementation: _NEW_IMPL, value: valueToLock});

        _xanProxy.castVote(_NEW_IMPL);
        vm.stopPrank();
    }

    function test_castVote_reverts_if_zero_tokens_have_been_locked() public {
        vm.prank(_defaultSender);

        vm.expectRevert(
            abi.encodeWithSelector(XanV1.LockedBalanceInsufficient.selector, _defaultSender, 0), address(_xanProxy)
        );
        _xanProxy.castVote(_NEW_IMPL);
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
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_NEW_IMPL);
        vm.stopPrank();
        assertEq(_NEW_IMPL, _xanProxy.proposedImplementationByRank(rank));

        // Check that no implementation has rank 1.
        rank = 1;
        vm.expectRevert(
            abi.encodeWithSelector(XanV1.ImplementationRankNonExistent.selector, 1, rank), address(_xanProxy)
        );
        _xanProxy.proposedImplementationByRank(rank);
    }

    function test_castVote_reverts_if_the_votum_has_already_been_casted() public {
        uint256 valueToLock = _xanProxy.totalSupply() / 3;

        vm.startPrank(_defaultSender);
        _xanProxy.lock(valueToLock);
        _xanProxy.castVote(_NEW_IMPL);

        vm.expectRevert(
            abi.encodeWithSelector(XanV1.LockedBalanceInsufficient.selector, _defaultSender, valueToLock),
            address(_xanProxy)
        );
        _xanProxy.castVote(_NEW_IMPL);

        vm.stopPrank();
    }

    function test_castVote_reverts_if_caller_has_no_locked_tokens() public {
        vm.prank(_defaultSender);
        vm.expectRevert(
            abi.encodeWithSelector(XanV1.LockedBalanceInsufficient.selector, _defaultSender, 0), address(_xanProxy)
        );
        _xanProxy.castVote(_NEW_IMPL);
    }

    function test_castVote_increases_votes_if_more_tokens_have_been_locked() public {
        uint256 firstLockValue = _xanProxy.totalSupply() / 3;
        uint256 secondLockValue = _xanProxy.totalSupply() - firstLockValue;

        vm.startPrank(_defaultSender);

        _xanProxy.lock(firstLockValue);
        _xanProxy.castVote(_NEW_IMPL);
        assertEq(_xanProxy.totalVotes(_NEW_IMPL), firstLockValue);

        _xanProxy.lock(secondLockValue);
        _xanProxy.castVote(_NEW_IMPL);
        assertEq(_xanProxy.totalVotes(_NEW_IMPL), firstLockValue + secondLockValue);

        vm.stopPrank();
    }

    function test_castVote_sets_the_votes_of_the_caller_to_the_locked_balance() public {
        uint256 firstLockValue = _xanProxy.totalSupply() / 3;
        uint256 secondLockValue = _xanProxy.totalSupply() - firstLockValue;

        vm.startPrank(_defaultSender);
        assertEq(_xanProxy.votum(_NEW_IMPL), 0);

        _xanProxy.lock(firstLockValue);
        _xanProxy.castVote(_NEW_IMPL);

        assertEq(_xanProxy.votum(_NEW_IMPL), firstLockValue);

        _xanProxy.lock(secondLockValue);
        _xanProxy.castVote(_NEW_IMPL);

        assertEq(_xanProxy.votum(_NEW_IMPL), firstLockValue + secondLockValue);
        vm.stopPrank();
    }

    function test_revokeVote_emits_the_VoteRevoked_event() public {
        uint256 valueToLock = _xanProxy.totalSupply() / 2;

        vm.startPrank(_defaultSender);
        _xanProxy.lock(valueToLock);
        _xanProxy.castVote(_NEW_IMPL);

        vm.expectEmit(address(_xanProxy));
        emit IXanV1.VoteRevoked({voter: _defaultSender, implementation: _NEW_IMPL, value: valueToLock});

        _xanProxy.revokeVote(_NEW_IMPL);
        vm.stopPrank();
    }

    function test_revokeVote_sets_the_votes_of_the_caller_to_zero() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(_xanProxy.totalSupply());
        _xanProxy.castVote(_NEW_IMPL);
        assertEq(_xanProxy.votum(_NEW_IMPL), _xanProxy.totalSupply());

        _xanProxy.revokeVote(_NEW_IMPL);
        assertEq(_xanProxy.votum(_NEW_IMPL), 0);
        vm.stopPrank();
    }

    function test_revokeVote_subtracts_the_old_votum_from_the_total_votes() public {
        uint256 votesReceiver = _xanProxy.totalSupply() / 3;
        uint256 votesDefaultSender = _xanProxy.totalSupply() - votesReceiver;

        // Send tokens to `_RECEIVER` from `_defaultSender` lock them.
        vm.startPrank(_defaultSender);
        _xanProxy.transferAndLock({to: _RECEIVER, value: votesReceiver});

        // Vote as `_defaultSender`.
        _xanProxy.lock(votesDefaultSender);
        _xanProxy.castVote(_NEW_IMPL);
        vm.stopPrank();

        // Vote as `_RECEIVER`.
        vm.prank(_RECEIVER);
        _xanProxy.castVote(_NEW_IMPL);
        assertEq(_xanProxy.totalVotes(_NEW_IMPL), votesDefaultSender + votesReceiver);

        // Revoke the vote as `_defaultSender` and
        vm.startPrank(_defaultSender);
        _xanProxy.revokeVote(_NEW_IMPL);

        // Check that the total votes are correct.
        assertEq(_xanProxy.totalVotes(_NEW_IMPL), votesReceiver);
        vm.stopPrank();
    }

    function test_revokeVote_reverts_if_the_voter_has_not_voted_on_the_proposal() public {
        vm.expectRevert(
            abi.encodeWithSelector(XanV1.NoVotesToRevoke.selector, _defaultSender, _NEW_IMPL), address(_xanProxy)
        );
        vm.prank(_defaultSender);
        _xanProxy.revokeVote(_NEW_IMPL);
    }

    function test_scheduleVoterBodyUpgrade_starts_the_delay_if_locked_supply_and_quorum_are_met_and_the_impl_is_ranked_best(
    ) public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_NEW_IMPL);
        vm.stopPrank();

        assertGe(_xanProxy.lockedSupply(), Parameters.MIN_LOCKED_SUPPLY);

        assertGt(_xanProxy.totalVotes(_NEW_IMPL), _xanProxy.calculateQuorumThreshold());
        assertEq(_xanProxy.proposedImplementationByRank(0), _NEW_IMPL);

        _xanProxy.scheduleVoterBodyUpgrade(_NEW_IMPL);

        assertEq(_xanProxy.scheduledVoterBodyUpgrade().impl, _NEW_IMPL);
        assertEq(_xanProxy.scheduledVoterBodyUpgrade().endTime, Time.timestamp() + Parameters.DELAY_DURATION);
    }

    function test_scheduleVoterBodyUpgrade_emits_the_DelayStarted_event() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(_xanProxy.totalSupply());
        _xanProxy.castVote(_NEW_IMPL);
        vm.stopPrank();

        vm.expectEmit(address(_xanProxy));
        emit IXanV1.VoterBodyUpgradeScheduled(
            IXanV1.ScheduledUpgrade({impl: _NEW_IMPL, endTime: Time.timestamp() + Parameters.DELAY_DURATION})
        );
        _xanProxy.scheduleVoterBodyUpgrade(_NEW_IMPL);
    }

    function test_scheduleVoterBodyUpgrade_reverts_if_the_minimal_locked_supply_is_not_met() public {
        vm.startPrank(_defaultSender);
        // Lock first half.
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY - 1);

        vm.expectRevert(abi.encodeWithSelector(XanV1.MinLockedSupplyNotReached.selector), address(_xanProxy));
        _xanProxy.scheduleVoterBodyUpgrade(_NEW_IMPL);
    }

    function test_scheduleVoterBodyUpgrade_reverts_if_quorum_is_not_met() public {
        uint256 quorumThreshold =
            (_xanProxy.totalSupply() * Parameters.QUORUM_RATIO_NUMERATOR) / Parameters.QUORUM_RATIO_DENOMINATOR;

        vm.startPrank(_defaultSender);
        // Lock first half.
        _xanProxy.lock(quorumThreshold);
        // Vote with first half.
        _xanProxy.castVote(_NEW_IMPL);

        // Lock second half.
        _xanProxy.lock(quorumThreshold);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(XanV1.QuorumNotReached.selector, _NEW_IMPL), address(_xanProxy));
        _xanProxy.scheduleVoterBodyUpgrade(_NEW_IMPL);
    }

    function test_scheduleVoterBodyUpgrade_reverts_if_delay_has_already_been_started() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_NEW_IMPL);
        vm.stopPrank();

        // Schedule the upgrade
        uint48 endTime = Time.timestamp() + Parameters.DELAY_DURATION;
        _xanProxy.scheduleVoterBodyUpgrade(_NEW_IMPL);

        // Try to start the delay again.
        vm.expectRevert(
            abi.encodeWithSelector(
                XanV1.UpgradeAlreadyScheduled.selector, IXanV1.ScheduledUpgrade({impl: _NEW_IMPL, endTime: endTime})
            ),
            address(_xanProxy)
        );
        _xanProxy.scheduleVoterBodyUpgrade(_NEW_IMPL);
    }

    function test_scheduleVoterBodyUpgrade_reverts_is_not_ranked_best() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_NEW_IMPL);
        _xanProxy.castVote(_OTHER_NEW_IMPL);
        vm.stopPrank();

        assertEq(_xanProxy.proposedImplementationByRank(0), _NEW_IMPL);
        assertEq(_xanProxy.proposedImplementationByRank(1), _OTHER_NEW_IMPL);

        vm.expectRevert(
            abi.encodeWithSelector(XanV1.ImplementationNotRankedBest.selector, _NEW_IMPL, _OTHER_NEW_IMPL),
            address(_xanProxy)
        );
        _xanProxy.scheduleVoterBodyUpgrade(_OTHER_NEW_IMPL);
    }

    function test_cancelVoterBodyUpgrade_reverts_on_winning_implementation() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_NEW_IMPL);
        vm.stopPrank();

        // Schedule the upgrade
        uint48 endTime = Time.timestamp() + Parameters.DELAY_DURATION;
        _xanProxy.scheduleVoterBodyUpgrade(_NEW_IMPL);

        // Skip the delay period.
        skip(Parameters.DELAY_DURATION);

        vm.expectRevert(
            abi.encodeWithSelector(
                XanV1.UpgradeCancellationInvalid.selector, IXanV1.ScheduledUpgrade({impl: _NEW_IMPL, endTime: endTime})
            ),
            address(_xanProxy)
        );
        _xanProxy.cancelVoterBodyUpgrade();
    }

    function test_cancelVoterBodyUpgrade_emits_the_DelayReset_event() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_NEW_IMPL);

        uint48 endTime = Time.timestamp() + Parameters.DELAY_DURATION;
        _xanProxy.scheduleVoterBodyUpgrade(_NEW_IMPL);

        // Vote with more weight for another implementation
        _xanProxy.lock(1);
        _xanProxy.castVote(_OTHER_NEW_IMPL);
        vm.stopPrank();

        assertEq(_xanProxy.proposedImplementationByRank(0), _OTHER_NEW_IMPL);
        assertEq(_xanProxy.proposedImplementationByRank(1), _NEW_IMPL);

        // Advance to the end of the delay period.
        skip(Parameters.DELAY_DURATION);

        // Cancel the upgrade
        vm.expectEmit(address(_xanProxy));
        emit IXanV1.VoterBodyUpgradeCancelled(IXanV1.ScheduledUpgrade({impl: _NEW_IMPL, endTime: endTime}));
        _xanProxy.cancelVoterBodyUpgrade();
    }

    function test_cancelVoterBodyUpgrade_resets_the_delay() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_NEW_IMPL);

        uint48 endTime = Time.timestamp() + Parameters.DELAY_DURATION;
        _xanProxy.scheduleVoterBodyUpgrade(_NEW_IMPL);

        assertEq(_xanProxy.scheduledVoterBodyUpgrade().impl, _NEW_IMPL);
        assertEq(_xanProxy.scheduledVoterBodyUpgrade().endTime, endTime);

        // Vote with more weight for another implementation
        _xanProxy.lock(1);
        _xanProxy.castVote(_OTHER_NEW_IMPL);
        vm.stopPrank();

        assertEq(_xanProxy.proposedImplementationByRank(0), _OTHER_NEW_IMPL);
        assertEq(_xanProxy.proposedImplementationByRank(1), _NEW_IMPL);

        // Advance to the end of the delay period.
        skip(Parameters.DELAY_DURATION);

        // Cancel the upgrade
        _xanProxy.cancelVoterBodyUpgrade();

        // Check state change has happened
        assertEq(_xanProxy.scheduledVoterBodyUpgrade().impl, address(0));
        assertEq(_xanProxy.scheduledVoterBodyUpgrade().endTime, 0);
    }

    function test_scheduleVoterBodyUpgrade_returns_the_upgrade_if_one_has_been_scheduled() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_NEW_IMPL);

        uint48 endTime = Time.timestamp() + Parameters.DELAY_DURATION;
        _xanProxy.scheduleVoterBodyUpgrade(_NEW_IMPL);

        assertEq(_xanProxy.scheduledVoterBodyUpgrade().impl, _NEW_IMPL);
        assertEq(_xanProxy.scheduledVoterBodyUpgrade().endTime, endTime);
    }

    function test_scheduledVoterBodyImplementation_returns_0_if_no_upgrade_has_been_scheduled() public view {
        assertEq(_xanProxy.scheduledVoterBodyUpgrade().impl, address(0));
        assertEq(_xanProxy.scheduledVoterBodyUpgrade().endTime, 0);
    }
}
