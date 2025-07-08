// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";

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

    // TODO! Remove
    /*function test_castVote_ranks_an_implementation_on_first_vote() public {
        // Check that no implementation has rank 0.
        uint48 count = _xanProxy.proposedImplementationsCount();
        uint48 rank = 0;

        vm.expectRevert(
            abi.encodeWithSelector(XanV1.ImplementationRankNonExistent.selector, count, rank), address(_xanProxy)
        );
        _xanProxy.proposedImplementationByRank(rank);

        // Lock, vote, and check that there is an implementation with rank 0.
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_NEW_IMPL);
        vm.stopPrank();

        count = _xanProxy.proposedImplementationsCount();
        assertEq(count, 1);

        assertEq(_NEW_IMPL, _xanProxy.proposedImplementationByRank(rank));

        // Check that no implementation has rank 1.
        rank = 1;
        vm.expectRevert(
            abi.encodeWithSelector(XanV1.ImplementationRankNonExistent.selector, count, rank), address(_xanProxy)
        );
        _xanProxy.proposedImplementationByRank(rank);
    }*/

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

    function test_castVote_updated_the_most_voted_implementationTODOTOD() public {
        revert("TODO?");
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

    function test_updateMostVotedImplementation_sets_an_implementation_as_the_most_voted_if_it_has_more_votes_than_the_current_one(
    ) public {
        revert("TODO");
    }

    function test_updateMostVotedImplementation_reverts_if_the_proposed_implementation_has_less_votes_than_the_current_one(
    ) public {
        revert("TODO");
    }

    function test_updateMostVotedImplementation_DEMONSTRATE_BEHAVIOR() public {
        revert("TODO");
    }

    function test_scheduleVoterBodyUpgrade_reverts_if_the_minimal_locked_supply_is_not_met() public {
        vm.startPrank(_defaultSender);
        // Lock first half.
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY - 1);
        _xanProxy.castVote(_NEW_IMPL);
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(
                XanV1.QuorumOrMinLockedSupplyNotReached.selector, _xanProxy.mostVotedImplementation()
            ),
            address(_xanProxy)
        );
        _xanProxy.scheduleVoterBodyUpgrade();
    }

    function test_scheduleVoterBodyUpgrade_reverts_if_quorum_is_not_met() public {
        uint256 quorumThreshold =
            (_xanProxy.totalSupply() * Parameters.QUORUM_RATIO_NUMERATOR) / Parameters.QUORUM_RATIO_DENOMINATOR;

        vm.startPrank(_defaultSender);
        // Lock first half.
        _xanProxy.lock(quorumThreshold);
        // Vote with first half.
        _xanProxy.castVote(_NEW_IMPL);
        _xanProxy.updateMostVotedImplementation(_NEW_IMPL);

        // Lock second half.
        _xanProxy.lock(quorumThreshold);
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(XanV1.QuorumOrMinLockedSupplyNotReached.selector, _NEW_IMPL), address(_xanProxy)
        );
        _xanProxy.scheduleVoterBodyUpgrade();
    }

    function test_scheduleVoterBodyUpgrade_reverts_if_delay_has_already_been_started() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_NEW_IMPL);
        _xanProxy.updateMostVotedImplementation(_NEW_IMPL);
        vm.stopPrank();

        // Schedule the upgrade
        uint48 endTime = Time.timestamp() + Parameters.DELAY_DURATION;
        _xanProxy.scheduleVoterBodyUpgrade();

        // Try to start the delay again.
        vm.expectRevert(
            abi.encodeWithSelector(XanV1.UpgradeAlreadyScheduled.selector, _NEW_IMPL, endTime), address(_xanProxy)
        );
        _xanProxy.scheduleVoterBodyUpgrade();
    }

    function test_scheduleVoterBodyUpgrade_schedules_the_most_voted_implementation() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_NEW_IMPL);
        _xanProxy.updateMostVotedImplementation(_NEW_IMPL);
        vm.stopPrank();

        _xanProxy.updateMostVotedImplementation(_NEW_IMPL);

        _xanProxy.scheduleVoterBodyUpgrade();

        (address scheduledImpl,) = _xanProxy.scheduledVoterBodyUpgrade();
        assertEq(scheduledImpl, _NEW_IMPL);
    }

    function test_scheduleVoterBodyUpgrade_starts_the_delay_if_locked_supply_and_quorum_are_met_and_the_impl_is_ranked_best(
    ) public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_NEW_IMPL);
        _xanProxy.updateMostVotedImplementation(_NEW_IMPL);
        vm.stopPrank();

        _xanProxy.updateMostVotedImplementation(_NEW_IMPL);

        assertGe(_xanProxy.lockedSupply(), Parameters.MIN_LOCKED_SUPPLY);

        assertGt(_xanProxy.totalVotes(_NEW_IMPL), _xanProxy.calculateQuorumThreshold());
        assertEq(_xanProxy.mostVotedImplementation(), _NEW_IMPL);

        _xanProxy.scheduleVoterBodyUpgrade();

        (address impl, uint48 endTime) = _xanProxy.scheduledVoterBodyUpgrade();
        assertEq(impl, _NEW_IMPL);
        assertEq(endTime, Time.timestamp() + Parameters.DELAY_DURATION);
    }

    function test_scheduleVoterBodyUpgrade_cancels_a_scheduled_upgrade_by_the_council_before_the_delay_has_passed()
        public
    {
        // Schedule `_OTHER_NEW_IMPL` with the council.
        vm.prank(_COUNCIL);
        _xanProxy.scheduleCouncilUpgrade(_OTHER_NEW_IMPL);
        (, uint48 endTime) = _xanProxy.scheduledCouncilUpgrade();

        // Vote on `_NEW_IMPL` with the voter body.
        vm.startPrank(_defaultSender);
        _xanProxy.lock(_xanProxy.totalSupply());
        _xanProxy.castVote(_NEW_IMPL);
        _xanProxy.updateMostVotedImplementation(_NEW_IMPL);
        vm.stopPrank();

        // Ensure that the delay has NOT passed.
        assertLt(Time.timestamp() + 24 hours, endTime);

        // Schedule `_NEW_IMPL` with the voter body
        vm.expectEmit(address(_xanProxy));
        emit IXanV1.VoterBodyUpgradeScheduled(_NEW_IMPL, Time.timestamp() + Parameters.DELAY_DURATION);

        vm.expectEmit(address(_xanProxy));
        emit IXanV1.CouncilUpgradeVetoed(_OTHER_NEW_IMPL);
        _xanProxy.scheduleVoterBodyUpgrade();
    }

    function test_scheduleVoterBodyUpgrade_cancels_a_scheduled_upgrade_by_the_council_after_the_delay_has_passed()
        public
    {
        // Schedule `_OTHER_NEW_IMPL` with the council.
        vm.prank(_COUNCIL);
        _xanProxy.scheduleCouncilUpgrade(_OTHER_NEW_IMPL);
        (, uint48 endTime) = _xanProxy.scheduledCouncilUpgrade();

        // Vote on `_NEW_IMPL` with the voter body.
        vm.startPrank(_defaultSender);
        _xanProxy.lock(_xanProxy.totalSupply());
        _xanProxy.castVote(_NEW_IMPL);
        _xanProxy.updateMostVotedImplementation(_NEW_IMPL);
        vm.stopPrank();

        // Ensure that the delay has just passed.
        skip(Parameters.DELAY_DURATION + 1);
        assertGt(Time.timestamp(), endTime);

        // Schedule `_NEW_IMPL` with the voter body
        vm.expectEmit(address(_xanProxy));
        emit IXanV1.VoterBodyUpgradeScheduled(_NEW_IMPL, Time.timestamp() + Parameters.DELAY_DURATION);

        vm.expectEmit(address(_xanProxy));
        emit IXanV1.CouncilUpgradeVetoed(_OTHER_NEW_IMPL);
        _xanProxy.scheduleVoterBodyUpgrade();
    }

    function test_scheduleVoterBodyUpgrade_cancels_a_scheduled_upgrade_by_the_council_and_resets_the_scheduled_upgrade_to_zero(
    ) public {
        // Schedule `_OTHER_NEW_IMPL` with the council.
        vm.prank(_COUNCIL);
        uint48 expectedEndTime = Time.timestamp() + Parameters.DELAY_DURATION;
        _xanProxy.scheduleCouncilUpgrade(_OTHER_NEW_IMPL);
        (address impl, uint48 endTime) = _xanProxy.scheduledCouncilUpgrade();
        assertEq(impl, _OTHER_NEW_IMPL);
        assertEq(endTime, expectedEndTime);

        // Vote on `_NEW_IMPL` with the voter body.
        vm.startPrank(_defaultSender);
        _xanProxy.lock(_xanProxy.totalSupply());
        _xanProxy.castVote(_NEW_IMPL);
        _xanProxy.updateMostVotedImplementation(_NEW_IMPL);
        vm.stopPrank();

        // Schedule `_NEW_IMPL` with the voter body
        _xanProxy.scheduleVoterBodyUpgrade();

        // Check that the council upgrade has been reset
        (impl, endTime) = _xanProxy.scheduledCouncilUpgrade();
        assertEq(impl, address(0));
        assertEq(endTime, 0);
    }

    function test_scheduleVoterBodyUpgrade_emits_the_DelayStarted_event() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(_xanProxy.totalSupply());
        _xanProxy.castVote(_NEW_IMPL);
        _xanProxy.updateMostVotedImplementation(_NEW_IMPL);
        vm.stopPrank();

        vm.expectEmit(address(_xanProxy));
        emit IXanV1.VoterBodyUpgradeScheduled(_NEW_IMPL, Time.timestamp() + Parameters.DELAY_DURATION);

        _xanProxy.scheduleVoterBodyUpgrade();
    }

    function test_cancelVoterBodyUpgrade_reverts_if_the_delay_period_has_not_started() public {
        // Ensure that an implementation is the best-ranked
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_NEW_IMPL);
        _xanProxy.updateMostVotedImplementation(_NEW_IMPL);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(XanV1.DelayPeriodNotStarted.selector, 0), address(_xanProxy));
        _xanProxy.cancelVoterBodyUpgrade();
    }

    function test_cancelVoterBodyUpgrade_reverts_if_the_delay_period_has_not_ended() public {
        // Ensure that an implementation is the best-ranked
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_NEW_IMPL);
        _xanProxy.updateMostVotedImplementation(_NEW_IMPL);
        vm.stopPrank();

        // Schedule the upgrade
        uint48 expectedEndTime = Time.timestamp() + Parameters.DELAY_DURATION;
        _xanProxy.scheduleVoterBodyUpgrade();

        vm.expectRevert(abi.encodeWithSelector(XanV1.DelayPeriodNotEnded.selector, expectedEndTime), address(_xanProxy));
        _xanProxy.cancelVoterBodyUpgrade();
    }

    function test_cancelVoterBodyUpgrade_reverts_after_the_delay_has_passed_when_attempting_to_cancel_the_best_ranked_implementation(
    ) public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_NEW_IMPL);
        _xanProxy.updateMostVotedImplementation(_NEW_IMPL);
        vm.stopPrank();

        // Schedule the upgrade
        uint48 endTime = Time.timestamp() + Parameters.DELAY_DURATION;
        _xanProxy.scheduleVoterBodyUpgrade();

        // Skip the delay period.
        skip(Parameters.DELAY_DURATION);

        vm.expectRevert(
            abi.encodeWithSelector(XanV1.UpgradeCancellationInvalid.selector, _NEW_IMPL, endTime), address(_xanProxy)
        );
        _xanProxy.cancelVoterBodyUpgrade();
    }

    function test_cancelVoterBodyUpgrade_emits_the_DelayReset_event() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_NEW_IMPL);
        _xanProxy.updateMostVotedImplementation(_NEW_IMPL);
        _xanProxy.scheduleVoterBodyUpgrade();

        // Vote with more weight for another implementation
        _xanProxy.lock(1);
        _xanProxy.castVote(_OTHER_NEW_IMPL);
        _xanProxy.updateMostVotedImplementation(_NEW_IMPL);
        vm.stopPrank();

        assertEq(_xanProxy.mostVotedImplementation(), _OTHER_NEW_IMPL);

        // Advance to the end of the delay period.
        skip(Parameters.DELAY_DURATION);

        // Cancel the upgrade
        vm.expectEmit(address(_xanProxy));
        emit IXanV1.VoterBodyUpgradeCancelled(_NEW_IMPL);
        _xanProxy.cancelVoterBodyUpgrade();
    }

    function test_cancelVoterBodyUpgrade_resets_the_delay() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_NEW_IMPL);
        _xanProxy.updateMostVotedImplementation(_NEW_IMPL);

        uint48 endTime = Time.timestamp() + Parameters.DELAY_DURATION;
        _xanProxy.scheduleVoterBodyUpgrade();

        (address scheduledImpl, uint48 scheduledEndTime) = _xanProxy.scheduledVoterBodyUpgrade();
        assertEq(scheduledImpl, _NEW_IMPL);
        assertEq(scheduledEndTime, endTime);

        // Vote with more weight for another implementation
        _xanProxy.lock(1);
        _xanProxy.castVote(_OTHER_NEW_IMPL);
        _xanProxy.updateMostVotedImplementation(_OTHER_NEW_IMPL);
        vm.stopPrank();

        assertEq(_xanProxy.mostVotedImplementation(), _OTHER_NEW_IMPL);

        // Advance to the end of the delay period.
        skip(Parameters.DELAY_DURATION);

        // Cancel the upgrade
        _xanProxy.cancelVoterBodyUpgrade();

        // Check state change has happened
        (scheduledImpl, scheduledEndTime) = _xanProxy.scheduledVoterBodyUpgrade();
        assertEq(scheduledImpl, address(0));
        assertEq(scheduledEndTime, 0);
    }

    function test_cancelVoterBodyUpgrade_cancels_a_scheduled_upgrade_after_the_delay_if_the_implementation_is_not_the_best_ranked_anymore(
    ) public {
        // Vote for `_NEW_IMPL`
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_NEW_IMPL);
        _xanProxy.updateMostVotedImplementation(_NEW_IMPL);
        vm.stopPrank();

        // Schedule the upgrade for `_NEW_IMPL`
        _xanProxy.scheduleVoterBodyUpgrade();

        // Skip the delay period.
        skip(Parameters.DELAY_DURATION);

        // Lock more tokens and vote for `_OTHER_NEW_IMPL`.
        vm.startPrank(_defaultSender);
        _xanProxy.lock(1);
        _xanProxy.castVote(_OTHER_NEW_IMPL);
        _xanProxy.updateMostVotedImplementation(_OTHER_NEW_IMPL);
        vm.stopPrank();

        // Check that `_OTHER_NEW_IMPL` is now the best-ranked implementation.
        assertEq(_xanProxy.mostVotedImplementation(), _OTHER_NEW_IMPL);

        // Cancel the upgrade for `_NEW_IMPL`;
        vm.expectEmit(address(_xanProxy));
        emit IXanV1.VoterBodyUpgradeCancelled(_NEW_IMPL);
        _xanProxy.cancelVoterBodyUpgrade();
    }

    function test_scheduleVoterBodyUpgrade_returns_the_upgrade_if_one_has_been_scheduled() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_NEW_IMPL);
        _xanProxy.updateMostVotedImplementation(_NEW_IMPL);

        uint48 endTime = Time.timestamp() + Parameters.DELAY_DURATION;
        _xanProxy.scheduleVoterBodyUpgrade();

        (address scheduledImpl, uint48 scheduledEndTime) = _xanProxy.scheduledVoterBodyUpgrade();
        assertEq(scheduledImpl, _NEW_IMPL);
        assertEq(scheduledEndTime, endTime);
    }

    function test_scheduledVoterBodyImplementation_returns_0_if_no_upgrade_has_been_scheduled() public view {
        (address scheduledImpl, uint48 scheduledEndTime) = _xanProxy.scheduledVoterBodyUpgrade();
        assertEq(scheduledImpl, address(0));
        assertEq(scheduledEndTime, 0);
    }
}
