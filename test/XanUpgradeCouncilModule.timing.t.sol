// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

import {Parameters} from "../src/libs/Parameters.sol";
import {XanUpgradeCouncilModule} from "../src/XanUpgradeCouncilModule.sol";
import {XanUpgradeCouncilModuleFixture} from "./fixtures/XanUpgradeCouncilModuleFixture.sol";

/// @notice Regression tests for the schedule-then-raise attack: the council schedules an upgrade and, in the same
/// transaction, executes an already-passed voter-body proposal raising the timing settings, so every later cancel
/// cycle would outrun a deadline frozen at scheduling.
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

    /// @notice A raise whose voting period alone outlasts the whole delay the upgrade was scheduled with, so no
    /// bound sized against that delay could have covered it.
    /// @dev `immutable`, not `constant`, so the narrowing to the `uint32` a voting period is stays checked — a
    /// `constant` initializer cannot call `SafeCast`.
    uint32 private immutable _VOTING_PERIOD_EXCEEDING_UPGRADE_DELAY = (_UPGRADE_DELAY + 1 days).toUint32();

    uint256 private immutable _UPGRADE_DELAY_AT_EXCEEDING_PERIOD =
        _UPGRADE_DELAY - Parameters.GOVERNOR_VOTING_PERIOD + _VOTING_PERIOD_EXCEEDING_UPGRADE_DELAY;

    /// @notice A passed voting-period raise waits in the timelock; the council schedules an upgrade and executes the
    /// raise in one batch, so the timelock's frozen deadline is computed from the old settings while every
    /// cancellation runs at the new ones.
    function test_voter_body_can_cancel_after_a_queued_settings_raise_executes_post_scheduling() public {
        assertGt(
            _VOTING_PERIOD_EXCEEDING_UPGRADE_DELAY,
            _UPGRADE_DELAY,
            "the voting period alone must outlast the delay the upgrade was scheduled with"
        );
        assertGt(
            _UPGRADE_DELAY_AT_EXCEEDING_PERIOD - Parameters.COUNCIL_EXTRA_DELAY,
            _UPGRADE_DELAY,
            "the raised cancel cycle must outrun the frozen deadline, or there is no race to close"
        );

        // A passed proposal raising the voting period, queued and past its timelock delay but not executed — an
        // ordinary state, since nobody is obliged to execute promptly.
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) =
            _queueVotingPeriodChange(_VOTING_PERIOD_EXCEEDING_UPGRADE_DELAY);
        skip(_timelock.getMinDelay() + 1 seconds);

        // The council's move: schedule the upgrade, then execute the raise, leaving no block in between for a
        // cancellation to be filed under the old settings.
        address newImpl = _newImplementation();
        (bytes32 operationId, uint48 scheduledAt) = _scheduleCouncilUpgrade(newImpl, "");
        uint256 frozenExecutableAt = scheduledAt + _module.upgradeDelay();
        _governor.execute(targets, values, calldatas, descriptionHash);
        assertEq(_governor.votingPeriod(), _VOTING_PERIOD_EXCEEDING_UPGRADE_DELAY);
        assertEq(_module.upgradeDelay(), _UPGRADE_DELAY_AT_EXCEEDING_PERIOD);

        uint256 recomputedExecutableAt = scheduledAt + _module.upgradeDelay();
        assertGt(
            recomputedExecutableAt,
            frozenExecutableAt,
            "the raise must push the recomputed deadline past the one the timelock froze"
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

    /// @notice Settings lowered after scheduling cannot pull the deadline in, because the timelock's frozen
    /// timestamp still applies. The effective deadline is the later of the two.
    function test_a_settings_cut_after_scheduling_does_not_shorten_the_upgrade_delay() public {
        address newImpl = _newImplementation();
        (bytes32 operationId, uint48 scheduledAt) = _scheduleCouncilUpgrade(newImpl, "");
        uint256 frozenExecutableAt = scheduledAt + _module.upgradeDelay();

        _passVotingPeriodChange(_HALVED_VOTING_PERIOD);
        assertEq(_module.upgradeDelay(), _UPGRADE_DELAY_AT_HALVED_PERIOD);
        assertLt(
            scheduledAt + _module.upgradeDelay(),
            frozenExecutableAt,
            "the cut must pull the recomputed deadline in, leaving only the frozen one binding"
        );

        // The timelock still holds the operation until its own frozen deadline.
        vm.warp(frozenExecutableAt - 1 seconds);
        _expectTimelockOperationNotReady(operationId);
        _executeCouncilUpgrade(newImpl, "", scheduledAt);

        vm.warp(frozenExecutableAt);
        _executeCouncilUpgrade(newImpl, "", scheduledAt);
        assertEq(_xanToken.implementation(), newImpl);
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
        _passProposal({targets: targets, values: values, calldatas: calldatas, description: "change the voting period"});
    }

    /// @notice Queues (but does not execute) a proposal setting the governor's voting period.
    function _queueVotingPeriodChange(uint32 newVotingPeriod)
        private
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash)
    {
        (targets, values, calldatas) = _setVotingPeriodCall(newVotingPeriod);
        descriptionHash = _queueVoterBodyProposal({
            targets: targets, values: values, calldatas: calldatas, description: "change the voting period"
        });
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
