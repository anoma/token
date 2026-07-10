// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {IXanUpgradeCouncil} from "../src/interfaces/IXanUpgradeCouncil.sol";
import {Parameters} from "../src/libs/Parameters.sol";
import {XanUpgradeCouncil} from "../src/XanUpgradeCouncil.sol";
import {XanUpgradeCouncilFixture} from "./fixtures/XanUpgradeCouncilFixture.sol";
import {MockXanV2} from "./mocks/MockXanV2.sol";

contract XanUpgradeCouncilTest is XanUpgradeCouncilFixture {
    function test_constructor_reverts_if_the_governor_is_the_zero_address() public {
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        vm.expectRevert(IXanUpgradeCouncil.ZeroGovernorNotAllowed.selector, predicted);
        new XanUpgradeCouncil({
            governor: IGovernor(address(0)),
            timelock: _timelock,
            token: address(_xanToken),
            initialCouncil: _COUNCIL_MULTISIG,
            cancelBuffer: Parameters.COUNCIL_CANCEL_BUFFER
        });
    }

    function test_constructor_reverts_if_the_timelock_is_the_zero_address() public {
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        vm.expectRevert(IXanUpgradeCouncil.ZeroTimelockNotAllowed.selector, predicted);
        new XanUpgradeCouncil({
            governor: IGovernor(address(_governor)),
            timelock: TimelockController(payable(address(0))),
            token: address(_xanToken),
            initialCouncil: _COUNCIL_MULTISIG,
            cancelBuffer: Parameters.COUNCIL_CANCEL_BUFFER
        });
    }

    function test_constructor_reverts_if_the_token_is_the_zero_address() public {
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        vm.expectRevert(IXanUpgradeCouncil.ZeroTokenNotAllowed.selector, predicted);
        new XanUpgradeCouncil({
            governor: IGovernor(address(_governor)),
            timelock: _timelock,
            token: address(0),
            initialCouncil: _COUNCIL_MULTISIG,
            cancelBuffer: Parameters.COUNCIL_CANCEL_BUFFER
        });
    }

    function test_constructor_reverts_if_the_initial_council_is_the_zero_address() public {
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)), predicted);
        new XanUpgradeCouncil({
            governor: IGovernor(address(_governor)),
            timelock: _timelock,
            token: address(_xanToken),
            initialCouncil: address(0),
            cancelBuffer: Parameters.COUNCIL_CANCEL_BUFFER
        });
    }

    function test_scheduleUpgrade_reverts_if_the_caller_is_not_the_council() public {
        address newImpl = _newImplementation();
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)),
            address(_upgradeCouncil)
        );
        _upgradeCouncil.scheduleUpgrade(newImpl, "");
    }

    function test_scheduleUpgrade_reverts_if_the_implementation_is_the_zero_address() public {
        vm.prank(_COUNCIL_MULTISIG);
        vm.expectRevert(IXanUpgradeCouncil.ZeroImplementationNotAllowed.selector, address(_upgradeCouncil));
        _upgradeCouncil.scheduleUpgrade(address(0), "");
    }

    function test_scheduleUpgrade_reverts_if_an_upgrade_is_already_pending() public {
        address first = _newImplementation();
        address second = _newImplementation();

        vm.prank(_COUNCIL_MULTISIG);
        _upgradeCouncil.scheduleUpgrade(first, "");

        bytes32 pending = _upgradeCouncil.pendingUpgrade();
        vm.prank(_COUNCIL_MULTISIG);
        vm.expectRevert(
            abi.encodeWithSelector(IXanUpgradeCouncil.UpgradeAlreadyPending.selector, pending),
            address(_upgradeCouncil)
        );
        _upgradeCouncil.scheduleUpgrade(second, "");
    }

    function test_scheduleUpgrade_can_be_rescheduled_after_a_cancel() public {
        address newImpl = _newImplementation();

        vm.prank(_COUNCIL_MULTISIG);
        _upgradeCouncil.scheduleUpgrade(newImpl, "");
        bytes32 firstId = _upgradeCouncil.pendingUpgrade();

        // Withdraw the upgrade, clearing the in-flight slot.
        vm.prank(_COUNCIL_MULTISIG);
        _upgradeCouncil.cancelUpgrade();
        assertFalse(_timelock.isOperationPending(firstId));

        // The cancelled operation is no longer pending, so the same upgrade re-schedules: this exercises the
        // `!isOperationPending` branch of the in-flight guard (the first schedule took the `== bytes32(0)` branch).
        // The deterministic salt makes the re-scheduled id identical to the first.
        vm.prank(_COUNCIL_MULTISIG);
        bytes32 secondId = _upgradeCouncil.scheduleUpgrade(newImpl, "");
        assertEq(secondId, firstId);
        assertTrue(_timelock.isOperationPending(secondId));
    }

    function test_scheduleUpgrade_lets_the_council_schedule_a_backup_upgrade() public {
        address newImpl = _newImplementation();

        (address target, bytes memory payload, bytes32 salt) = _councilUpgradeCall(newImpl, "");
        bytes32 expectedId =
            _timelock.hashOperation({target: target, value: 0, data: payload, predecessor: bytes32(0), salt: salt});
        uint256 executableAt = block.timestamp + _upgradeCouncil.cancelWindow();

        vm.expectEmit(address(_upgradeCouncil));
        emit IXanUpgradeCouncil.UpgradeScheduled({
            newImplementation: newImpl, operationId: expectedId, data: "", executableAt: executableAt
        });

        vm.prank(_COUNCIL_MULTISIG);
        _upgradeCouncil.scheduleUpgrade(newImpl, "");

        // Wait out the cancel window, then anyone executes via the timelock.
        skip(_upgradeCouncil.cancelWindow() + 1);
        _executeCouncilUpgrade(newImpl, "");

        assertEq(_xanToken.implementation(), newImpl);
    }

    function test_scheduleUpgrade_forwards_arbitrary_upgrade_data() public {
        address newImpl = _newImplementation();
        // A non-empty payload forwarded verbatim to `upgradeToAndCall`; `clock()` is just an always-succeeding call,
        // not a reinitializer.
        bytes memory data = abi.encodeWithSelector(_xanToken.clock.selector);

        // The data is part of the salt, so the same upgrade with data has a different operation id than without it.
        (address emptyTarget, bytes memory emptyPayload, bytes32 emptySalt) = _councilUpgradeCall(newImpl, "");
        bytes32 emptyId = _timelock.hashOperation({
            target: emptyTarget, value: 0, data: emptyPayload, predecessor: bytes32(0), salt: emptySalt
        });
        (address target, bytes memory payload, bytes32 salt) = _councilUpgradeCall(newImpl, data);
        bytes32 expectedId =
            _timelock.hashOperation({target: target, value: 0, data: payload, predecessor: bytes32(0), salt: salt});
        assertTrue(expectedId != emptyId);

        // The event carries the forwarded calldata verbatim.
        vm.expectEmit(address(_upgradeCouncil));
        emit IXanUpgradeCouncil.UpgradeScheduled({
            newImplementation: newImpl,
            operationId: expectedId,
            data: data,
            executableAt: block.timestamp + _upgradeCouncil.cancelWindow()
        });

        vm.prank(_COUNCIL_MULTISIG);
        bytes32 operationId = _upgradeCouncil.scheduleUpgrade(newImpl, data);
        assertEq(operationId, expectedId);

        // Execution forwards `data` to `upgradeToAndCall`, so the upgrade applies and the payload runs without
        // reverting.
        skip(_upgradeCouncil.cancelWindow() + 1);
        _timelock.execute({target: target, value: 0, payload: payload, predecessor: bytes32(0), salt: salt});
        assertEq(_xanToken.implementation(), newImpl);
    }

    function test_scheduleUpgrade_cannot_be_executed_before_the_delay() public {
        address newImpl = _newImplementation();
        vm.prank(_COUNCIL_MULTISIG);
        _upgradeCouncil.scheduleUpgrade(newImpl, "");

        // One second before the window closes the operation is not yet executable.
        skip(_upgradeCouncil.cancelWindow() - 1);
        (address target, bytes memory payload, bytes32 salt) = _councilUpgradeCall(newImpl, "");
        bytes32 execId =
            _timelock.hashOperation({target: target, value: 0, data: payload, predecessor: bytes32(0), salt: salt});
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockUnexpectedOperationState.selector,
                execId,
                _timelockStateBitmap(TimelockController.OperationState.Ready)
            ),
            address(_timelock)
        );
        _timelock.execute({target: target, value: 0, payload: payload, predecessor: bytes32(0), salt: salt});
    }

    function test_voter_body_can_cancel_a_council_upgrade_through_the_governor() public {
        address newImpl = _newImplementation();
        vm.prank(_COUNCIL_MULTISIG);
        _upgradeCouncil.scheduleUpgrade(newImpl, "");
        bytes32 operationId = _upgradeCouncil.pendingUpgrade();

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(_governor);
        bytes memory cancelCall = abi.encodeCall(TimelockController.cancel, (operationId));
        calldatas[0] = abi.encodeCall(Governor.relay, (address(_timelock), uint256(0), cancelCall));

        _passProposal({
            targets: targets, values: values, calldatas: calldatas, description: "cancel the council upgrade"
        });

        // The council upgrade is cancelled; it can no longer be executed even after the cancel window.
        assertFalse(_timelock.isOperationPending(operationId));
        skip(_upgradeCouncil.cancelWindow() + 1);
        (address target, bytes memory payload, bytes32 salt) = _councilUpgradeCall(newImpl, "");
        bytes32 execId =
            _timelock.hashOperation({target: target, value: 0, data: payload, predecessor: bytes32(0), salt: salt});
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockUnexpectedOperationState.selector,
                execId,
                _timelockStateBitmap(TimelockController.OperationState.Ready)
            ),
            address(_timelock)
        );
        _timelock.execute({target: target, value: 0, payload: payload, predecessor: bytes32(0), salt: salt});
    }

    function test_cancelUpgrade_lets_the_council_withdraw_its_own_upgrade() public {
        address newImpl = _newImplementation();
        vm.prank(_COUNCIL_MULTISIG);
        _upgradeCouncil.scheduleUpgrade(newImpl, "");
        bytes32 operationId = _upgradeCouncil.pendingUpgrade();

        vm.expectEmit(address(_upgradeCouncil));
        emit IXanUpgradeCouncil.UpgradeCancelled(operationId);

        vm.prank(_COUNCIL_MULTISIG);
        bytes32 cancelledId = _upgradeCouncil.cancelUpgrade();

        assertEq(cancelledId, operationId);
        assertFalse(_timelock.isOperationPending(operationId));
    }

    function test_cancelUpgrade_reverts_if_no_upgrade_was_scheduled() public {
        vm.prank(_COUNCIL_MULTISIG);
        vm.expectRevert(IXanUpgradeCouncil.NoUpgradePending.selector, address(_upgradeCouncil));
        _upgradeCouncil.cancelUpgrade();
    }

    function test_cancelUpgrade_reverts_if_the_upgrade_is_no_longer_pending() public {
        address newImpl = _newImplementation();
        vm.prank(_COUNCIL_MULTISIG);
        _upgradeCouncil.scheduleUpgrade(newImpl, "");

        vm.prank(_COUNCIL_MULTISIG);
        _upgradeCouncil.cancelUpgrade();

        // A second cancel of the same (now-cancelled) upgrade reverts: the operation is no longer pending.
        vm.prank(_COUNCIL_MULTISIG);
        vm.expectRevert(IXanUpgradeCouncil.NoUpgradePending.selector, address(_upgradeCouncil));
        _upgradeCouncil.cancelUpgrade();
    }

    function test_cancelUpgrade_reverts_if_the_caller_is_not_the_council() public {
        address newImpl = _newImplementation();
        vm.prank(_COUNCIL_MULTISIG);
        _upgradeCouncil.scheduleUpgrade(newImpl, "");

        vm.prank(_OTHER);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _OTHER), address(_upgradeCouncil)
        );
        _upgradeCouncil.cancelUpgrade();
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
        bytes32 councilOperationId = _upgradeCouncil.scheduleUpgrade(councilImpl, "");

        vm.prank(_COUNCIL_MULTISIG);
        bytes32 cancelledId = _upgradeCouncil.cancelUpgrade();

        // Only the council's own operation is gone; the voter-body operation is untouched.
        assertEq(cancelledId, councilOperationId);
        assertFalse(_timelock.isOperationPending(councilOperationId));
        assertTrue(_timelock.isOperationPending(voterOperationId));
    }

    /// @notice Voter supremacy is structural: the council has no cancel power over voter-body operations, so a
    /// standalone `transferOwnership` rotation passes unhindered and the ousted council loses its privileges.
    function test_voter_body_can_rotate_the_council_through_the_governor() public {
        address replacementCouncil = makeAddr("replacementCouncil");
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(_upgradeCouncil);
        calldatas[0] = abi.encodeCall(Ownable.transferOwnership, (replacementCouncil));

        bytes32 descriptionHash = _queueVoterBodyProposal(targets, values, calldatas, "replace the council");

        skip(_timelock.getMinDelay() + 1);
        _governor.execute({targets: targets, values: values, calldatas: calldatas, descriptionHash: descriptionHash});
        assertEq(_upgradeCouncil.owner(), replacementCouncil);

        // The ousted council is now powerless: its privileged entry points reject it.
        address newImpl = _newImplementation();
        vm.prank(_COUNCIL_MULTISIG);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _COUNCIL_MULTISIG),
            address(_upgradeCouncil)
        );
        _upgradeCouncil.scheduleUpgrade(newImpl, "");
    }

    function test_transferOwnership_lets_the_voter_body_rotate_the_council() public {
        address newCouncil = makeAddr("newCouncil");

        vm.expectEmit(address(_upgradeCouncil));
        emit Ownable.OwnershipTransferred({previousOwner: _COUNCIL_MULTISIG, newOwner: newCouncil});

        vm.prank(address(_timelock));
        _upgradeCouncil.transferOwnership(newCouncil);
        assertEq(_upgradeCouncil.owner(), newCouncil);
    }

    function test_transferOwnership_lets_the_council_hand_off() public {
        address newCouncil = makeAddr("newCouncil");

        vm.prank(_COUNCIL_MULTISIG);
        _upgradeCouncil.transferOwnership(newCouncil);
        assertEq(_upgradeCouncil.owner(), newCouncil);
    }

    function test_transferOwnership_reverts_if_the_caller_is_neither_owner_nor_timelock() public {
        vm.prank(_OTHER);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _OTHER), address(_upgradeCouncil)
        );
        _upgradeCouncil.transferOwnership(makeAddr("newCouncil"));
    }

    function test_transferOwnership_reverts_if_the_new_owner_is_the_zero_address() public {
        vm.prank(address(_timelock));
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)), address(_upgradeCouncil)
        );
        _upgradeCouncil.transferOwnership(address(0));
    }

    function test_cancelWindow_exceeds_the_voter_cancel_cycle() public view {
        uint256 voterCancelCycle = _governor.votingDelay() + _governor.votingPeriod() + _timelock.getMinDelay();
        assertEq(_upgradeCouncil.cancelWindow(), voterCancelCycle + Parameters.COUNCIL_CANCEL_BUFFER);
    }

    /// @notice Deploys a fresh implementation to upgrade the token to.
    function _newImplementation() internal returns (address newImpl) {
        newImpl = address(
            new MockXanV2({
                v1Implementation: _v1Implementation,
                owner: address(_timelock),
                vestingStart: Parameters.VESTING_START,
                vestingDuration: Parameters.VESTING_DURATION
            })
        );
    }

    /// @notice Executes a scheduled council upgrade through the (open-executor) timelock.
    function _executeCouncilUpgrade(address newImpl, bytes memory data) internal {
        (address target, bytes memory payload, bytes32 salt) = _councilUpgradeCall(newImpl, data);
        _timelock.execute({target: target, value: 0, payload: payload, predecessor: bytes32(0), salt: salt});
    }

    /// @notice Has the voter body propose, pass, and queue (but not execute) an arbitrary proposal.
    /// @return descriptionHash The hash of the proposal description, needed to rebuild its timelock operation id.
    function _queueVoterBodyProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) internal returns (bytes32 descriptionHash) {
        descriptionHash = keccak256(bytes(description));

        vm.prank(_voterA);
        uint256 proposalId =
            _governor.propose({targets: targets, values: values, calldatas: calldatas, description: description});

        _warpIntoVotingPeriod();
        vm.prank(_voterA);
        _governor.castVote(proposalId, uint8(1));

        _warpPastVotingPeriod();
        _governor.queue({targets: targets, values: values, calldatas: calldatas, descriptionHash: descriptionHash});
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

    /// @notice Rebuilds the council's upgrade call and salt (deterministic, matching the module).
    function _councilUpgradeCall(address newImpl, bytes memory data)
        internal
        view
        returns (address target, bytes memory payload, bytes32 salt)
    {
        target = address(_xanToken);
        payload = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (newImpl, data));
        salt = keccak256(abi.encode("XanUpgradeCouncil.upgrade", newImpl, data));
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

    /// @notice The single-state bitmap `TimelockController` uses to describe an operation's expected state in its
    /// `TimelockUnexpectedOperationState` error (mirrors OZ's internal `_encodeStateBitmap`).
    function _timelockStateBitmap(TimelockController.OperationState state) internal pure returns (bytes32 bitmap) {
        bitmap = bytes32(uint256(1) << uint8(state));
    }
}
