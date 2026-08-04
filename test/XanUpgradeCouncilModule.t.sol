// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

import {IXanUpgradeCouncilModule} from "../src/interfaces/IXanUpgradeCouncilModule.sol";
import {Parameters} from "../src/libs/Parameters.sol";
import {XanUpgradeCouncilModule} from "../src/XanUpgradeCouncilModule.sol";
import {XanUpgradeCouncilModuleFixture} from "./fixtures/XanUpgradeCouncilModuleFixture.sol";

contract XanUpgradeCouncilModuleTest is XanUpgradeCouncilModuleFixture {
    function test_constructor_reverts_if_the_governor_is_the_zero_address() public {
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        vm.expectRevert(XanUpgradeCouncilModule.ZeroGovernorNotAllowed.selector, predicted);
        new XanUpgradeCouncilModule({
            governor: IGovernor(address(0)),
            timelock: _timelock,
            council: _COUNCIL_MULTISIG,
            token: address(_xanToken),
            extraDelay: Parameters.COUNCIL_EXTRA_DELAY
        });
    }

    function test_constructor_reverts_if_the_timelock_is_the_zero_address() public {
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        vm.expectRevert(XanUpgradeCouncilModule.ZeroTimelockNotAllowed.selector, predicted);
        new XanUpgradeCouncilModule({
            governor: IGovernor(address(_governor)),
            timelock: TimelockController(payable(address(0))),
            council: _COUNCIL_MULTISIG,
            token: address(_xanToken),
            extraDelay: Parameters.COUNCIL_EXTRA_DELAY
        });
    }

    function test_constructor_reverts_if_the_token_is_the_zero_address() public {
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        vm.expectRevert(XanUpgradeCouncilModule.ZeroTokenNotAllowed.selector, predicted);
        new XanUpgradeCouncilModule({
            governor: IGovernor(address(_governor)),
            timelock: _timelock,
            council: _COUNCIL_MULTISIG,
            token: address(0),
            extraDelay: Parameters.COUNCIL_EXTRA_DELAY
        });
    }

    function test_constructor_reverts_if_the_council_is_the_zero_address() public {
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        vm.expectRevert(XanUpgradeCouncilModule.ZeroCouncilNotAllowed.selector, predicted);
        new XanUpgradeCouncilModule({
            governor: IGovernor(address(_governor)),
            timelock: _timelock,
            council: address(0),
            token: address(_xanToken),
            extraDelay: Parameters.COUNCIL_EXTRA_DELAY
        });
    }

    function test_constructor_reverts_if_the_extra_delay_is_zero() public {
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        vm.expectRevert(XanUpgradeCouncilModule.ZeroExtraDelayNotAllowed.selector, predicted);
        new XanUpgradeCouncilModule({
            governor: IGovernor(address(_governor)),
            timelock: _timelock,
            council: _COUNCIL_MULTISIG,
            token: address(_xanToken),
            extraDelay: 0
        });
    }

    function test_scheduleUpgrade_reverts_if_the_caller_is_not_the_council() public {
        address newImpl = _newImplementation();
        vm.expectRevert(
            abi.encodeWithSelector(XanUpgradeCouncilModule.UnauthorizedCouncil.selector, address(this)),
            address(_module)
        );
        _module.scheduleUpgrade(newImpl, "");
    }

    function test_scheduleUpgrade_reverts_if_the_implementation_is_the_zero_address() public {
        vm.prank(_COUNCIL_MULTISIG);
        vm.expectRevert(XanUpgradeCouncilModule.ZeroImplementationNotAllowed.selector, address(_module));
        _module.scheduleUpgrade(address(0), "");
    }

    function test_scheduleUpgrade_reverts_if_an_upgrade_is_already_pending() public {
        address first = _newImplementation();
        address second = _newImplementation();

        vm.prank(_COUNCIL_MULTISIG);
        _module.scheduleUpgrade(first, "");

        bytes32 pending = _module.getLastScheduledUpgradeOperationId();
        vm.prank(_COUNCIL_MULTISIG);
        vm.expectRevert(
            abi.encodeWithSelector(XanUpgradeCouncilModule.UpgradeAlreadyPending.selector, pending), address(_module)
        );
        _module.scheduleUpgrade(second, "");
    }

    function test_scheduleUpgrade_can_be_rescheduled_after_a_cancel() public {
        address newImpl = _newImplementation();

        vm.prank(_COUNCIL_MULTISIG);
        _module.scheduleUpgrade(newImpl, "");
        bytes32 firstId = _module.getLastScheduledUpgradeOperationId();

        // Withdraw the upgrade, clearing the in-flight slot.
        vm.prank(_COUNCIL_MULTISIG);
        _module.cancelUpgrade();
        assertFalse(_timelock.isOperationPending(firstId));

        // The cancelled operation is no longer pending, so the same upgrade re-schedules: this exercises the
        // `!isOperationPending` branch of the in-flight guard (the first schedule took the `== bytes32(0)` branch).
        // Re-scheduling in the same block reuses the schedule timestamp, so the id matches the first.
        vm.prank(_COUNCIL_MULTISIG);
        bytes32 secondId = _module.scheduleUpgrade(newImpl, "");
        assertEq(secondId, firstId);
        assertTrue(_timelock.isOperationPending(secondId));
    }

    /// @notice The schedule timestamp is baked into the batch's `checkUpgradeDelayElapsed` call, so an upgrade
    /// re-scheduled in a later block gets a fresh operation id even though the salt is unchanged.
    function test_scheduleUpgrade_yields_a_fresh_id_when_rescheduled_in_a_later_block() public {
        address newImpl = _newImplementation();

        (bytes32 firstId,) = _scheduleCouncilUpgrade(newImpl, "");
        vm.prank(_COUNCIL_MULTISIG);
        _module.cancelUpgrade();

        skip(1 seconds);
        (bytes32 secondId,) = _scheduleCouncilUpgrade(newImpl, "");

        assertTrue(secondId != firstId);
        assertTrue(_timelock.isOperationPending(secondId));
    }

    function test_scheduleUpgrade_lets_the_council_schedule_a_backup_upgrade() public {
        address newImpl = _newImplementation();

        bytes32 expectedId = _councilOperationId(newImpl, "", Time.timestamp());
        uint256 earliestExecutableAt = Time.timestamp() + _module.upgradeDelay();

        vm.expectEmit(address(_module));
        emit IXanUpgradeCouncilModule.UpgradeScheduled({
            newImplementation: newImpl,
            operationId: expectedId,
            data: "",
            scheduledAt: Time.timestamp(),
            earliestExecutableAt: earliestExecutableAt
        });

        (bytes32 operationId, uint48 scheduledAt) = _scheduleCouncilUpgrade(newImpl, "");
        assertEq(operationId, expectedId);

        // Wait out the upgrade delay, then anyone executes via the timelock.
        skip(_module.upgradeDelay() + 1 seconds);
        _executeCouncilUpgrade(newImpl, "", scheduledAt);

        assertEq(_xanToken.implementation(), newImpl);
    }

    function test_scheduleUpgrade_forwards_arbitrary_upgrade_data() public {
        address newImpl = _newImplementation();
        // A non-empty payload forwarded verbatim to `upgradeToAndCall`; `clock()` is just an always-succeeding call,
        // not a reinitializer.
        bytes memory data = abi.encodeWithSelector(_xanToken.clock.selector);

        // The data is part of the salt, so the same upgrade with data has a different operation id than without it.
        bytes32 emptyId = _councilOperationId(newImpl, "", Time.timestamp());
        bytes32 expectedId = _councilOperationId(newImpl, data, Time.timestamp());
        assertTrue(expectedId != emptyId);

        // The event carries the forwarded calldata verbatim.
        vm.expectEmit(address(_module));
        emit IXanUpgradeCouncilModule.UpgradeScheduled({
            newImplementation: newImpl,
            operationId: expectedId,
            data: data,
            scheduledAt: Time.timestamp(),
            earliestExecutableAt: Time.timestamp() + _module.upgradeDelay()
        });

        (bytes32 operationId, uint48 scheduledAt) = _scheduleCouncilUpgrade(newImpl, data);
        assertEq(operationId, expectedId);

        // Execution forwards `data` to `upgradeToAndCall`, so the upgrade applies and the payload runs without
        // reverting.
        skip(_module.upgradeDelay() + 1 seconds);
        _executeCouncilUpgrade(newImpl, data, scheduledAt);
        assertEq(_xanToken.implementation(), newImpl);
    }

    function test_scheduleUpgrade_cannot_be_executed_before_the_delay() public {
        address newImpl = _newImplementation();
        (bytes32 operationId, uint48 scheduledAt) = _scheduleCouncilUpgrade(newImpl, "");

        // One second before the window closes the timelock still holds the operation `Waiting`.
        skip(_module.upgradeDelay() - 1 seconds);
        _expectTimelockOperationNotReady(operationId);
        _executeCouncilUpgrade(newImpl, "", scheduledAt);
    }

    function test_voter_body_can_cancel_a_council_upgrade_through_the_governor() public {
        address newImpl = _newImplementation();
        (bytes32 operationId, uint48 scheduledAt) = _scheduleCouncilUpgrade(newImpl, "");

        _cancelCouncilUpgradeThroughGovernor(operationId);

        // The council upgrade is cancelled; it can no longer be executed even after the upgrade delay.
        assertFalse(_timelock.isOperationPending(operationId));
        skip(_module.upgradeDelay() + 1 seconds);
        _expectTimelockOperationNotReady(operationId);
        _executeCouncilUpgrade(newImpl, "", scheduledAt);
    }

    /// @notice A governor cancel frees the in-flight slot exactly like `cancelUpgrade` does, so the council isn't
    /// stuck: it can schedule a fresh upgrade right after the voter body cancels one.
    function test_scheduleUpgrade_can_be_rescheduled_after_a_governor_cancel() public {
        address newImpl = _newImplementation();
        vm.prank(_COUNCIL_MULTISIG);
        _module.scheduleUpgrade(newImpl, "");
        bytes32 firstId = _module.getLastScheduledUpgradeOperationId();

        _cancelCouncilUpgradeThroughGovernor(firstId);
        assertFalse(_timelock.isOperationPending(firstId));

        // The cancel cycle advanced time, so the re-scheduled upgrade carries a later schedule timestamp and a
        // correspondingly fresh operation id.
        vm.prank(_COUNCIL_MULTISIG);
        bytes32 secondId = _module.scheduleUpgrade(newImpl, "");
        assertTrue(secondId != firstId);
        assertTrue(_timelock.isOperationPending(secondId));
    }

    function test_cancelUpgrade_lets_the_council_withdraw_its_own_upgrade() public {
        address newImpl = _newImplementation();
        vm.prank(_COUNCIL_MULTISIG);
        _module.scheduleUpgrade(newImpl, "");
        bytes32 operationId = _module.getLastScheduledUpgradeOperationId();

        vm.expectEmit(address(_module));
        emit IXanUpgradeCouncilModule.UpgradeCancelled(operationId);

        vm.prank(_COUNCIL_MULTISIG);
        bytes32 cancelledId = _module.cancelUpgrade();

        assertEq(cancelledId, operationId);
        assertFalse(_timelock.isOperationPending(operationId));
    }

    function test_cancelUpgrade_reverts_if_no_upgrade_was_scheduled() public {
        vm.prank(_COUNCIL_MULTISIG);
        vm.expectRevert(XanUpgradeCouncilModule.NoUpgradePending.selector, address(_module));
        _module.cancelUpgrade();
    }

    function test_cancelUpgrade_reverts_if_the_upgrade_is_no_longer_pending() public {
        address newImpl = _newImplementation();
        vm.prank(_COUNCIL_MULTISIG);
        _module.scheduleUpgrade(newImpl, "");

        vm.prank(_COUNCIL_MULTISIG);
        _module.cancelUpgrade();

        // A second cancel of the same (now-cancelled) upgrade reverts: the operation is no longer pending.
        vm.prank(_COUNCIL_MULTISIG);
        vm.expectRevert(XanUpgradeCouncilModule.NoUpgradePending.selector, address(_module));
        _module.cancelUpgrade();
    }

    function test_cancelUpgrade_reverts_if_the_caller_is_not_the_council() public {
        address newImpl = _newImplementation();
        vm.prank(_COUNCIL_MULTISIG);
        _module.scheduleUpgrade(newImpl, "");

        vm.prank(_OTHER);
        vm.expectRevert(
            abi.encodeWithSelector(XanUpgradeCouncilModule.UnauthorizedCouncil.selector, _OTHER), address(_module)
        );
        _module.cancelUpgrade();
    }

    /// @notice The property replacing the removed general brake: the module's only cancel aims at its own pending
    /// upgrade, so a queued voter-body operation is untouchable by the council.
    function test_cancelUpgrade_only_cancels_the_council_upgrade() public {
        address voterImpl = _newImplementation();
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) =
            _queueVoterBodyUpgrade(voterImpl);
        bytes32 voterOperationId = _voterBodyOperationId({
            targets: targets, values: values, calldatas: calldatas, descriptionHash: descriptionHash
        });

        address councilImpl = _newImplementation();
        vm.prank(_COUNCIL_MULTISIG);
        bytes32 councilOperationId = _module.scheduleUpgrade(councilImpl, "");

        vm.prank(_COUNCIL_MULTISIG);
        bytes32 cancelledId = _module.cancelUpgrade();

        // Only the council's own operation is gone; the voter-body operation is untouched.
        assertEq(cancelledId, councilOperationId);
        assertFalse(_timelock.isOperationPending(councilOperationId));
        assertTrue(_timelock.isOperationPending(voterOperationId));
    }

    /// @notice Executing a council upgrade frees the one-in-flight slot, so the council can schedule the next one.
    function test_scheduleUpgrade_can_schedule_a_new_upgrade_after_execution() public {
        address first = _newImplementation();
        (, uint48 scheduledAt) = _scheduleCouncilUpgrade(first, "");

        skip(_module.upgradeDelay() + 1 seconds);
        _executeCouncilUpgrade(first, "", scheduledAt);
        assertEq(_xanToken.implementation(), first);

        address second = _newImplementation();
        vm.prank(_COUNCIL_MULTISIG);
        bytes32 secondId = _module.scheduleUpgrade(second, "");
        assertTrue(_timelock.isOperationPending(secondId));
    }

    /// @notice An executed upgrade is beyond recall: `cancelUpgrade` cannot rewind it.
    function test_cancelUpgrade_reverts_if_the_upgrade_was_already_executed() public {
        address newImpl = _newImplementation();
        (, uint48 scheduledAt) = _scheduleCouncilUpgrade(newImpl, "");

        skip(_module.upgradeDelay() + 1 seconds);
        _executeCouncilUpgrade(newImpl, "", scheduledAt);

        vm.prank(_COUNCIL_MULTISIG);
        vm.expectRevert(XanUpgradeCouncilModule.NoUpgradePending.selector, address(_module));
        _module.cancelUpgrade();
    }

    /// @notice The voter body's last resort: revoking the module's timelock roles disarms the council entirely. The
    /// timelock self-administers, so only a passed proposal (impersonated here) can do this — and only a passed
    /// proposal can undo it.
    function test_voter_body_can_disarm_the_module_by_revoking_its_roles() public {
        bytes32 proposerRole = _timelock.PROPOSER_ROLE();
        vm.startPrank(address(_timelock));
        _timelock.revokeRole(proposerRole, address(_module));
        _timelock.revokeRole(_timelock.CANCELLER_ROLE(), address(_module));
        vm.stopPrank();

        // The module's propose path is dead: the timelock rejects the role-less module.
        address newImpl = _newImplementation();
        vm.prank(_COUNCIL_MULTISIG);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(_module), proposerRole
            )
        );
        _module.scheduleUpgrade(newImpl, "");
    }

    /// @notice The upgrade delay is computed live from the timelock's `minDelay`, so an upgrade scheduled after a
    /// change of that delay is sized against it. Upgrades scheduled *before* a change are
    /// `checkUpgradeDelayElapsed`'s job, covered in `XanUpgradeCouncilModule.timing.t.sol`.
    function test_upgradeDelay_tracks_a_timelock_minDelay_change() public {
        uint256 upgradeDelayBefore = _module.upgradeDelay();
        uint256 delayBefore = _timelock.getMinDelay();

        // Only the timelock itself may update its delay; impersonating it stands in for a passed proposal.
        vm.prank(address(_timelock));
        _timelock.updateDelay(delayBefore * 2);

        assertEq(_module.upgradeDelay(), upgradeDelayBefore + delayBefore);
    }

    /// @notice The upgrade delay is computed live from the governor's settings, so an upgrade scheduled after a
    /// voter-body change of the voting period is sized against it.
    function test_upgradeDelay_tracks_a_governor_settings_change_through_governance() public {
        uint256 upgradeDelayBefore = _module.upgradeDelay();
        uint32 periodBefore = uint32(_governor.votingPeriod());

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(_governor);
        calldatas[0] = abi.encodeCall(GovernorSettings.setVotingPeriod, (periodBefore * 2));

        _passProposal({targets: targets, values: values, calldatas: calldatas, description: "double the voting period"});

        assertEq(_governor.votingPeriod(), uint256(periodBefore) * 2);
        assertEq(_module.upgradeDelay(), upgradeDelayBefore + periodBefore);
    }

    function test_getLastScheduledUpgradeOperationId_returns_the_operation_id_while_the_upgrade_is_pending() public {
        address newImpl = _newImplementation();
        vm.prank(_COUNCIL_MULTISIG);
        bytes32 operationId = _module.scheduleUpgrade(newImpl, "");

        assertEq(_module.getLastScheduledUpgradeOperationId(), operationId);

        // Still tracked right up to execution, even after the upgrade delay has elapsed.
        skip(_module.upgradeDelay() + 1 seconds);
        assertEq(_module.getLastScheduledUpgradeOperationId(), operationId);
    }

    function test_getLastScheduledUpgradeOperationId_still_returns_the_id_after_a_cancel() public {
        address newImpl = _newImplementation();
        vm.prank(_COUNCIL_MULTISIG);
        bytes32 operationId = _module.scheduleUpgrade(newImpl, "");

        vm.prank(_COUNCIL_MULTISIG);
        _module.cancelUpgrade();

        // The getter reports the tracked id regardless of timelock state; callers check pending state themselves.
        assertEq(_module.getLastScheduledUpgradeOperationId(), operationId);
    }

    function test_getLastScheduledUpgradeOperationId_still_returns_the_id_after_execution() public {
        address newImpl = _newImplementation();
        (bytes32 operationId, uint48 scheduledAt) = _scheduleCouncilUpgrade(newImpl, "");

        skip(_module.upgradeDelay() + 1 seconds);
        _executeCouncilUpgrade(newImpl, "", scheduledAt);

        assertEq(_module.getLastScheduledUpgradeOperationId(), operationId);
    }

    function test_getLastScheduledUpgradeOperationId_still_returns_the_id_after_a_governor_cancel() public {
        address newImpl = _newImplementation();
        vm.prank(_COUNCIL_MULTISIG);
        _module.scheduleUpgrade(newImpl, "");
        bytes32 operationId = _module.getLastScheduledUpgradeOperationId();

        _cancelCouncilUpgradeThroughGovernor(operationId);

        assertEq(_module.getLastScheduledUpgradeOperationId(), operationId);
    }

    function test_constructor_sets_the_timelock() public view {
        assertEq(_module.getTimelock(), address(_timelock));
    }

    function test_constructor_sets_the_council() public view {
        assertEq(_module.getCouncil(), _COUNCIL_MULTISIG);
    }

    function test_constructor_sets_the_governor() public view {
        assertEq(_module.getGovernor(), address(_governor));
    }

    function test_constructor_sets_the_token() public view {
        assertEq(_module.getToken(), address(_xanToken));
    }

    function test_constructor_sets_the_extra_delay() public view {
        assertEq(_module.getExtraDelay(), Parameters.COUNCIL_EXTRA_DELAY);
    }

    function test_getLastScheduledUpgradeOperationId_returns_zero_if_nothing_was_scheduled() public view {
        assertEq(_module.getLastScheduledUpgradeOperationId(), bytes32(0));
    }

    function test_upgradeDelay_exceeds_the_voter_cancel_cycle() public view {
        uint256 voterCancelCycle = _governor.votingDelay() + _governor.votingPeriod() + _timelock.getMinDelay();
        assertEq(_module.upgradeDelay(), voterCancelCycle + Parameters.COUNCIL_EXTRA_DELAY);
        assertGt(_module.upgradeDelay(), voterCancelCycle);
    }

    /// @notice Has the voter body propose, pass, and queue (but not execute) a token upgrade.
    function _queueVoterBodyUpgrade(address newImpl)
        internal
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash)
    {
        targets = new address[](1);
        values = new uint256[](1);
        calldatas = new bytes[](1);
        targets[0] = address(_xanToken);
        calldatas[0] = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (newImpl, ""));

        descriptionHash = _queueVoterBodyProposal(targets, values, calldatas, "voter-body upgrade");
    }

    /// @notice The timelock salt the governor derives from a proposal's description hash.
    function _voterBodySalt(bytes32 descriptionHash) internal view returns (bytes32 salt) {
        salt = bytes32(bytes20(address(_governor))) ^ descriptionHash;
    }

    /// @notice Computes the timelock operation id the governor assigns to a queued voter-body proposal.
    function _voterBodyOperationId(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal view returns (bytes32 operationId) {
        operationId = _timelock.hashOperationBatch({
            targets: targets,
            values: values,
            payloads: calldatas,
            predecessor: bytes32(0),
            salt: _voterBodySalt(descriptionHash)
        });
    }
}
