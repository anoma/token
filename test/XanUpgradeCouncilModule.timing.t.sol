// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

import {Parameters} from "../src/libs/Parameters.sol";
import {XanUpgradeCouncilModule} from "../src/XanUpgradeCouncilModule.sol";
import {XanUpgradeCouncilModuleFixture} from "./fixtures/XanUpgradeCouncilModuleFixture.sol";

/// @notice Tests for timing settings that change while a council upgrade is pending: an increase after scheduling
/// pushes the deadline out, a decrease cannot pull it in, and an increase undone by a later decrease lets the upgrade
/// outrun a cancel already in flight.
/// @dev Runs at the production governor settings. The base fixture's compressed ones hide the race, moving the cancel
/// cycle by seconds against a days-scale margin.
contract XanUpgradeCouncilModuleTimingTest is XanUpgradeCouncilModuleFixture {
    using SafeCast for uint256;

    /// @notice `upgradeDelay` at production settings, and so the delay every upgrade below is scheduled with.
    uint256 private constant _UPGRADE_DELAY = Parameters.GOVERNOR_VOTING_DELAY + Parameters.GOVERNOR_VOTING_PERIOD
        + Parameters.TIMELOCK_MIN_DELAY + Parameters.COUNCIL_EXTRA_DELAY;

    uint32 private constant _HALVED_VOTING_PERIOD = Parameters.GOVERNOR_VOTING_PERIOD / 2;

    uint256 private constant _UPGRADE_DELAY_AT_HALVED_PERIOD =
        _UPGRADE_DELAY - Parameters.GOVERNOR_VOTING_PERIOD + _HALVED_VOTING_PERIOD;

    /// @notice How much of `COUNCIL_EXTRA_DELAY` is left when the voter body files its cancel proposal — the latest
    /// start the margin is meant to cover.
    uint256 private constant _MARGIN_LEFT_AT_CANCEL = 1 hours;

    /// @notice Shared by every voting-period proposal below, so queueing and executing one derive the same salt.
    string private constant _VOTING_PERIOD_CHANGE_DESCRIPTION = "change the voting period";

    /// @notice An increase whose voting period alone outlasts the whole delay the upgrade was scheduled with, so no
    /// bound sized against that delay could have covered it.
    /// @dev `immutable`, not `constant`, so the narrowing to the `uint32` a voting period is stays checked — a
    /// `constant` initializer cannot call `SafeCast`.
    uint32 private immutable _VOTING_PERIOD_EXCEEDING_UPGRADE_DELAY = (_UPGRADE_DELAY + 1 days).toUint32();

    uint256 private immutable _UPGRADE_DELAY_AT_EXCEEDING_PERIOD =
        _UPGRADE_DELAY - Parameters.GOVERNOR_VOTING_PERIOD + _VOTING_PERIOD_EXCEEDING_UPGRADE_DELAY;

    /// @notice A passed voting-period increase waits in the timelock; the council schedules an upgrade and executes
    /// the increase in one batch, so the timelock's frozen deadline is computed from the old settings while every
    /// cancellation runs at the new ones.
    function test_voter_body_can_cancel_after_a_queued_delay_increase_executes_post_scheduling() public {
        assertGt(
            _VOTING_PERIOD_EXCEEDING_UPGRADE_DELAY,
            _UPGRADE_DELAY,
            "the voting period alone must outlast the delay the upgrade was scheduled with"
        );
        assertGt(
            _UPGRADE_DELAY_AT_EXCEEDING_PERIOD - Parameters.COUNCIL_EXTRA_DELAY,
            _UPGRADE_DELAY,
            "the increased cancel cycle must outrun the frozen deadline, or there is no race to close"
        );

        // A passed proposal increasing the voting period, queued and past its timelock delay but not executed — an
        // ordinary state, since nobody is obliged to execute promptly.
        _queueVotingPeriodChange(_VOTING_PERIOD_EXCEEDING_UPGRADE_DELAY);
        skip(_timelock.getMinDelay() + 1 seconds);

        // The council's move: schedule the upgrade, then execute the increase, leaving no block in between for a
        // cancellation to be filed under the old settings.
        address newImpl = _newImplementation();
        (bytes32 operationId, uint48 scheduledAt) = _scheduleCouncilUpgrade(newImpl, "");
        uint256 frozenExecutableAt = scheduledAt + _module.upgradeDelay();
        _executeVotingPeriodChange(_VOTING_PERIOD_EXCEEDING_UPGRADE_DELAY);
        assertEq(_governor.votingPeriod(), _VOTING_PERIOD_EXCEEDING_UPGRADE_DELAY);
        assertEq(_module.upgradeDelay(), _UPGRADE_DELAY_AT_EXCEEDING_PERIOD);

        uint256 recomputedExecutableAt = scheduledAt + _module.upgradeDelay();
        assertGt(
            recomputedExecutableAt,
            frozenExecutableAt,
            "the increase must push the recomputed deadline past the one the timelock froze"
        );

        // At the now-stale frozen deadline `checkUpgradeDelayElapsed` reverts, and the timelock keeps the operation
        // `Ready` for a later attempt.
        vm.warp(frozenExecutableAt + 1 seconds);
        vm.expectRevert(
            abi.encodeWithSelector(
                XanUpgradeCouncilModule.UpgradeDelayNotElapsed.selector, scheduledAt, recomputedExecutableAt
            ),
            address(_module)
        );
        _executeCouncilUpgrade(newImpl, "", scheduledAt);
        assertTrue(_timelock.isOperationReady(operationId));

        // The voter body starts its cancel cycle at the very edge of its margin and still finishes in time.
        vm.warp(scheduledAt + Parameters.COUNCIL_EXTRA_DELAY - _MARGIN_LEFT_AT_CANCEL);
        _cancelCouncilUpgradeThroughGovernor(operationId);
        assertLt(
            Time.timestamp(),
            recomputedExecutableAt,
            "the cancel cycle must finish before the upgrade becomes executable"
        );
        assertFalse(_timelock.isOperationPending(operationId));

        // The cancelled upgrade stays gone once the recomputed deadline passes.
        vm.warp(recomputedExecutableAt + 1 seconds);
        _expectTimelockOperationNotReady(operationId);
        _executeCouncilUpgrade(newImpl, "", scheduledAt);
    }

    /// @notice A delay decrease after scheduling cannot pull the deadline in, because the timelock's frozen
    /// timestamp still applies. The effective deadline is the later of the two.
    function test_a_delay_decrease_after_scheduling_does_not_shorten_the_upgrade_delay() public {
        address newImpl = _newImplementation();
        (bytes32 operationId, uint48 scheduledAt) = _scheduleCouncilUpgrade(newImpl, "");
        uint256 frozenExecutableAt = scheduledAt + _module.upgradeDelay();

        _passVotingPeriodChange(_HALVED_VOTING_PERIOD);
        assertEq(_module.upgradeDelay(), _UPGRADE_DELAY_AT_HALVED_PERIOD);
        assertLt(
            scheduledAt + _module.upgradeDelay(),
            frozenExecutableAt,
            "the decrease must pull the recomputed deadline in, leaving only the frozen one binding"
        );

        // The timelock still holds the operation until its own frozen deadline.
        vm.warp(frozenExecutableAt - 1 seconds);
        _expectTimelockOperationNotReady(operationId);
        _executeCouncilUpgrade(newImpl, "", scheduledAt);

        vm.warp(frozenExecutableAt);
        _executeCouncilUpgrade(newImpl, "", scheduledAt);
        assertEq(_xanToken.implementation(), newImpl);
    }

    /// @notice An increase executing after scheduling pushes the deadline out, and a later decrease restores the
    /// frozen one. A cancel cycle started in between keeps the increased voting period — `XanGovernor` snapshots it at
    /// proposal creation — so it no longer finishes in time. The voter body prevents this by never leaving contrary
    /// settings proposals queued at once, there being no on-chain recourse once the decrease is queued.
    function test_a_delay_decrease_undoing_an_increase_lets_the_upgrade_outrun_an_in_flight_cancel() public {
        // Contrary settings proposals, both passed and queued past their timelock delay, neither executed.
        _queueVotingPeriodChange(_VOTING_PERIOD_EXCEEDING_UPGRADE_DELAY);
        _queueVotingPeriodChange(Parameters.GOVERNOR_VOTING_PERIOD);
        skip(_timelock.getMinDelay() + 1 seconds);

        address newImpl = _newImplementation();
        (bytes32 operationId, uint48 scheduledAt) = _scheduleCouncilUpgrade(newImpl, "");
        uint256 frozenExecutableAt = scheduledAt + _module.upgradeDelay();

        _executeVotingPeriodChange(_VOTING_PERIOD_EXCEEDING_UPGRADE_DELAY);
        assertEq(_module.upgradeDelay(), _UPGRADE_DELAY_AT_EXCEEDING_PERIOD);
        uint256 increasedExecutableAt = scheduledAt + _module.upgradeDelay();
        assertGt(increasedExecutableAt, frozenExecutableAt, "the increase must push the deadline past the frozen one");

        // The voter body starts its cancel cycle at the edge of its margin, sized against the increased deadline.
        vm.warp(scheduledAt + Parameters.COUNCIL_EXTRA_DELAY - _MARGIN_LEFT_AT_CANCEL);
        uint256 cancelCompletesAt = _proposeCancelCouncilUpgrade(operationId) + _timelock.getMinDelay();
        assertLt(cancelCompletesAt, increasedExecutableAt, "the cancel must fit inside the increased deadline");

        // Undoing the increase restores the frozen deadline, which the cycle already under way cannot meet.
        _executeVotingPeriodChange(Parameters.GOVERNOR_VOTING_PERIOD);
        assertEq(
            scheduledAt + _module.upgradeDelay(), frozenExecutableAt, "the decrease must restore the frozen deadline"
        );
        assertGt(cancelCompletesAt, frozenExecutableAt, "the cancel under way must now miss the deadline");

        vm.warp(frozenExecutableAt);
        _executeCouncilUpgrade(newImpl, "", scheduledAt);
        assertEq(_xanToken.implementation(), newImpl, "the upgrade lands before the cancel can complete");
    }

    /// @notice `checkUpgradeDelayElapsed` is callable by anyone, for off-chain monitoring, and passes exactly at
    /// `scheduledAt + upgradeDelay()`.
    function test_checkUpgradeDelayElapsed_reverts_until_the_recomputed_delay_has_elapsed() public {
        uint256 delay = _module.upgradeDelay();
        skip(delay);

        // An upgrade scheduled exactly `delay` ago passes; one scheduled a second later does not.
        uint48 executableNow = (vm.getBlockTimestamp() - delay).toUint48();
        _module.checkUpgradeDelayElapsed(executableNow);

        uint48 oneSecondShort = executableNow + 1 seconds;
        vm.expectRevert(
            abi.encodeWithSelector(
                XanUpgradeCouncilModule.UpgradeDelayNotElapsed.selector, oneSecondShort, oneSecondShort + delay
            ),
            address(_module)
        );
        _module.checkUpgradeDelayElapsed(oneSecondShort);
    }

    function _votingDelay() internal pure override returns (uint48 votingDelay) {
        votingDelay = Parameters.GOVERNOR_VOTING_DELAY;
    }

    function _votingPeriod() internal pure override returns (uint32 votingPeriod) {
        votingPeriod = Parameters.GOVERNOR_VOTING_PERIOD;
    }

    function _passVotingPeriodChange(uint32 newVotingPeriod) private {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            _setVotingPeriodCall(newVotingPeriod);
        _passProposal({
            targets: targets, values: values, calldatas: calldatas, description: _VOTING_PERIOD_CHANGE_DESCRIPTION
        });
    }

    /// @notice Queues (but does not execute) a proposal setting the governor's voting period.
    function _queueVotingPeriodChange(uint32 newVotingPeriod) private {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            _setVotingPeriodCall(newVotingPeriod);
        _queueVoterBodyProposal({
            targets: targets, values: values, calldatas: calldatas, description: _VOTING_PERIOD_CHANGE_DESCRIPTION
        });
    }

    /// @notice Executes a voting-period change already queued by `_queueVotingPeriodChange`.
    function _executeVotingPeriodChange(uint32 newVotingPeriod) private {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            _setVotingPeriodCall(newVotingPeriod);
        _governor.execute(targets, values, calldatas, keccak256(bytes(_VOTING_PERIOD_CHANGE_DESCRIPTION)));
    }

    /// @notice Files the voter body's cancel proposal without running it to completion.
    /// @return voteEnd The timestamp the cancel proposal's voting closes at, fixed by the settings in force now.
    function _proposeCancelCouncilUpgrade(bytes32 operationId) private returns (uint256 voteEnd) {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            _cancelCouncilUpgradeCall(operationId);

        vm.prank(_voterA);
        uint256 proposalId = _governor.propose(targets, values, calldatas, "cancel the council upgrade");
        voteEnd = _governor.proposalDeadline(proposalId);
    }

    function _setVotingPeriodCall(uint32 newVotingPeriod)
        private
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    {
        targets = new address[](1);
        values = new uint256[](1);
        calldatas = new bytes[](1);
        targets[0] = address(_governor);
        calldatas[0] = abi.encodeCall(GovernorSettings.setVotingPeriod, (newVotingPeriod));
    }
}
