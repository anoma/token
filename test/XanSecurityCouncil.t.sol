// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {IXanSecurityCouncil} from "../src/interfaces/IXanSecurityCouncil.sol";
import {Parameters} from "../src/libs/Parameters.sol";
import {XanSecurityCouncil} from "../src/XanSecurityCouncil.sol";
import {MockXanV2} from "./mocks/MockXanV2.sol";
import {XanSecurityCouncilFixture} from "./XanSecurityCouncilFixture.sol";

contract XanSecurityCouncilTest is XanSecurityCouncilFixture {
    function test_constructor_reverts_if_the_governor_is_the_zero_address() public {
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        vm.expectRevert(IXanSecurityCouncil.ZeroGovernorNotAllowed.selector, predicted);
        new XanSecurityCouncil({
            governor: IGovernor(address(0)),
            timelock: _timelock,
            token: address(_xanToken),
            initialCouncil: _COUNCIL_MULTISIG,
            cancelBuffer: Parameters.COUNCIL_CANCEL_BUFFER
        });
    }

    function test_constructor_reverts_if_the_timelock_is_the_zero_address() public {
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        vm.expectRevert(IXanSecurityCouncil.ZeroTimelockNotAllowed.selector, predicted);
        new XanSecurityCouncil({
            governor: IGovernor(address(_governor)),
            timelock: TimelockController(payable(address(0))),
            token: address(_xanToken),
            initialCouncil: _COUNCIL_MULTISIG,
            cancelBuffer: Parameters.COUNCIL_CANCEL_BUFFER
        });
    }

    function test_constructor_reverts_if_the_token_is_the_zero_address() public {
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        vm.expectRevert(IXanSecurityCouncil.ZeroTokenNotAllowed.selector, predicted);
        new XanSecurityCouncil({
            governor: IGovernor(address(_governor)),
            timelock: _timelock,
            token: address(0),
            initialCouncil: _COUNCIL_MULTISIG,
            cancelBuffer: Parameters.COUNCIL_CANCEL_BUFFER
        });
    }

    function test_constructor_reverts_if_the_initial_council_is_the_zero_address() public {
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        vm.expectRevert(IXanSecurityCouncil.ZeroCouncilNotAllowed.selector, predicted);
        new XanSecurityCouncil({
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
            abi.encodeWithSelector(IXanSecurityCouncil.UnauthorizedCouncil.selector, address(this)),
            address(_securityCouncil)
        );
        _securityCouncil.scheduleUpgrade(newImpl, "");
    }

    function test_scheduleUpgrade_reverts_if_the_implementation_is_the_zero_address() public {
        vm.prank(_COUNCIL_MULTISIG);
        vm.expectRevert(IXanSecurityCouncil.ZeroImplementationNotAllowed.selector, address(_securityCouncil));
        _securityCouncil.scheduleUpgrade(address(0), "");
    }

    function test_scheduleUpgrade_reverts_if_an_upgrade_is_already_pending() public {
        address first = _newImplementation();
        address second = _newImplementation();

        vm.prank(_COUNCIL_MULTISIG);
        _securityCouncil.scheduleUpgrade(first, "");

        bytes32 pending = _securityCouncil.pendingUpgrade();
        vm.prank(_COUNCIL_MULTISIG);
        vm.expectRevert(
            abi.encodeWithSelector(IXanSecurityCouncil.UpgradeAlreadyPending.selector, pending),
            address(_securityCouncil)
        );
        _securityCouncil.scheduleUpgrade(second, "");
    }

    function test_scheduleUpgrade_lets_the_council_fast_track_an_upgrade() public {
        address newImpl = _newImplementation();

        (address target, bytes memory payload, bytes32 salt) = _councilUpgradeCall(newImpl, "");
        bytes32 expectedId =
            _timelock.hashOperation({target: target, value: 0, data: payload, predecessor: bytes32(0), salt: salt});
        uint256 executableAt = block.timestamp + _securityCouncil.cancelWindow();

        vm.expectEmit(address(_securityCouncil));
        emit IXanSecurityCouncil.UpgradeScheduled({
            newImplementation: newImpl, operationId: expectedId, data: "", executableAt: executableAt
        });

        vm.prank(_COUNCIL_MULTISIG);
        _securityCouncil.scheduleUpgrade(newImpl, "");

        // Wait out the cancel window, then anyone executes via the timelock.
        skip(_securityCouncil.cancelWindow() + 1);
        _executeCouncilUpgrade(newImpl, "");

        assertEq(_xanToken.implementation(), newImpl);
    }

    function test_scheduleUpgrade_cannot_be_executed_before_the_delay() public {
        address newImpl = _newImplementation();
        vm.prank(_COUNCIL_MULTISIG);
        _securityCouncil.scheduleUpgrade(newImpl, "");

        // One second before the window closes the operation is not yet executable.
        skip(_securityCouncil.cancelWindow() - 1);
        (address target, bytes memory payload, bytes32 salt) = _councilUpgradeCall(newImpl, "");
        vm.expectRevert(address(_timelock));
        _timelock.execute({target: target, value: 0, payload: payload, predecessor: bytes32(0), salt: salt});
    }

    function test_voter_body_can_cancel_a_council_fast_track_through_the_governor() public {
        address newImpl = _newImplementation();
        vm.prank(_COUNCIL_MULTISIG);
        _securityCouncil.scheduleUpgrade(newImpl, "");
        bytes32 operationId = _securityCouncil.pendingUpgrade();

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
        skip(_securityCouncil.cancelWindow() + 1);
        (address target, bytes memory payload, bytes32 salt) = _councilUpgradeCall(newImpl, "");
        vm.expectRevert(address(_timelock));
        _timelock.execute({target: target, value: 0, payload: payload, predecessor: bytes32(0), salt: salt});
    }

    function test_cancel_lets_the_council_withdraw_its_own_fast_track() public {
        address newImpl = _newImplementation();
        vm.prank(_COUNCIL_MULTISIG);
        _securityCouncil.scheduleUpgrade(newImpl, "");
        bytes32 operationId = _securityCouncil.pendingUpgrade();

        // The council's own upgrade is a single-call operation, so it withdraws it through `cancel` (not
        // `cancelBatch`).
        (address target, bytes memory payload, bytes32 salt) = _councilUpgradeCall(newImpl, "");

        vm.expectEmit(address(_securityCouncil));
        emit IXanSecurityCouncil.ProposalCancelled(operationId);

        vm.prank(_COUNCIL_MULTISIG);
        bytes32 cancelledId = _securityCouncil.cancel({target: target, value: 0, data: payload, salt: salt});

        assertEq(cancelledId, operationId);
        assertFalse(_timelock.isOperationPending(operationId));
    }

    function test_cancel_reverts_if_the_operation_was_never_scheduled() public {
        // Nothing was scheduled, so the reconstructed id matches no pending operation and the timelock rejects it.
        address newImpl = _newImplementation();
        (address target, bytes memory payload, bytes32 salt) = _councilUpgradeCall(newImpl, "");

        vm.prank(_COUNCIL_MULTISIG);
        vm.expectRevert(address(_timelock));
        _securityCouncil.cancel({target: target, value: 0, data: payload, salt: salt});
    }

    function test_cancel_reverts_if_the_operation_is_no_longer_pending() public {
        address newImpl = _newImplementation();
        vm.prank(_COUNCIL_MULTISIG);
        _securityCouncil.scheduleUpgrade(newImpl, "");

        (address target, bytes memory payload, bytes32 salt) = _councilUpgradeCall(newImpl, "");
        vm.prank(_COUNCIL_MULTISIG);
        _securityCouncil.cancel({target: target, value: 0, data: payload, salt: salt});

        // A second cancel of the same (now-cancelled) operation reverts inside the timelock.
        vm.prank(_COUNCIL_MULTISIG);
        vm.expectRevert(address(_timelock));
        _securityCouncil.cancel({target: target, value: 0, data: payload, salt: salt});
    }

    function test_cancel_reverts_if_the_caller_is_not_the_council() public {
        address newImpl = _newImplementation();
        vm.prank(_COUNCIL_MULTISIG);
        _securityCouncil.scheduleUpgrade(newImpl, "");

        (address target, bytes memory payload, bytes32 salt) = _councilUpgradeCall(newImpl, "");
        vm.prank(_OTHER);
        vm.expectRevert(
            abi.encodeWithSelector(IXanSecurityCouncil.UnauthorizedCouncil.selector, _OTHER), address(_securityCouncil)
        );
        _securityCouncil.cancel({target: target, value: 0, data: payload, salt: salt});
    }

    function test_cancel_cannot_be_used_to_cancel_a_setCouncil_rotation() public {
        // The single-call `cancel` path enforces the same guard as `cancelBatch`: it refuses to cancel a `setCouncil`
        // rotation on this module, so a captured council cannot veto its own replacement. The guard trips on the call
        // shape alone, before any timelock lookup.
        bytes memory data = abi.encodeCall(IXanSecurityCouncil.setCouncil, (makeAddr("replacementCouncil")));
        vm.prank(_COUNCIL_MULTISIG);
        vm.expectRevert(IXanSecurityCouncil.CannotCancelCouncilRotation.selector, address(_securityCouncil));
        _securityCouncil.cancel({target: address(_securityCouncil), value: 0, data: data, salt: bytes32(0)});
    }

    function test_cancelBatch_lets_the_council_cancel_a_voter_body_upgrade() public {
        address newImpl = _newImplementation();
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) =
            _queueVoterBodyUpgrade(newImpl);
        bytes32 operationId = _voterBodyOperationId({
            targets: targets, values: values, calldatas: calldatas, descriptionHash: descriptionHash
        });
        assertTrue(_timelock.isOperationPending(operationId));

        vm.prank(_COUNCIL_MULTISIG);
        bytes32 cancelledId = _securityCouncil.cancelBatch({
            targets: targets, values: values, payloads: calldatas, salt: _voterBodySalt(descriptionHash)
        });

        assertEq(cancelledId, operationId);
        assertFalse(_timelock.isOperationPending(operationId));
    }

    function test_cancelBatch_cancels_a_voter_body_upgrade_bundled_with_other_actions() public {
        address newImpl = _newImplementation();

        // The upgrade is bundled with a second (benign) action, so the queued operation is a multi-action batch.
        // The council reconstructs the batch (its parameters are public on-chain) and cancels it; bundling, and any
        // batch shape other than a standalone `setCouncil`, stays cancellable.
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](2);
        targets[0] = _OTHER;
        calldatas[0] = "";
        targets[1] = address(_xanToken);
        calldatas[1] = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (newImpl, ""));

        bytes32 descriptionHash =
            _queueVoterBodyProposal(targets, values, calldatas, "upgrade bundled with another action");

        bytes32 operationId = _voterBodyOperationId({
            targets: targets, values: values, calldatas: calldatas, descriptionHash: descriptionHash
        });
        assertTrue(_timelock.isOperationPending(operationId));

        vm.prank(_COUNCIL_MULTISIG);
        _securityCouncil.cancelBatch({
            targets: targets, values: values, payloads: calldatas, salt: _voterBodySalt(descriptionHash)
        });

        assertFalse(_timelock.isOperationPending(operationId));
    }

    function test_cancelBatch_reverts_if_the_caller_is_not_the_council() public {
        address[] memory targets = new address[](0);
        uint256[] memory values = new uint256[](0);
        bytes[] memory payloads = new bytes[](0);
        vm.expectRevert(
            abi.encodeWithSelector(IXanSecurityCouncil.UnauthorizedCouncil.selector, address(this)),
            address(_securityCouncil)
        );
        _securityCouncil.cancelBatch({targets: targets, values: values, payloads: payloads, salt: bytes32(0)});
    }

    /// @notice The attack the `CannotCancelCouncilRotation` guard exists to stop: a captured council using its general
    /// brake to veto its own removal. Without the guard, the `cancelBatch` below succeeds, the rotation is deleted from
    /// the timelock, and the council can repeat this on every removal attempt, entrenching itself forever.
    function test_cancelBatch_cannot_be_used_to_cancel_a_setCouncil_rotation() public {
        // The voter body moves to replace the (captured) council with a fresh multisig: a standalone `setCouncil`.
        address replacementCouncil = makeAddr("replacementCouncil");
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(_securityCouncil);
        calldatas[0] = abi.encodeCall(IXanSecurityCouncil.setCouncil, (replacementCouncil));

        string memory description = "remove the captured council";
        bytes32 descriptionHash = _queueVoterBodyProposal(targets, values, calldatas, description);

        bytes32 operationId = _voterBodyOperationId({
            targets: targets, values: values, calldatas: calldatas, descriptionHash: descriptionHash
        });
        assertTrue(_timelock.isOperationPending(operationId));

        // The entrenchment attempt: the captured council fires its brake at its own removal. The guard blocks it.
        // (Delete the guard and this `cancelBatch` succeeds, the assertion below fails, and the council survives.)
        vm.prank(_COUNCIL_MULTISIG);
        vm.expectRevert(IXanSecurityCouncil.CannotCancelCouncilRotation.selector, address(_securityCouncil));
        _securityCouncil.cancelBatch({
            targets: targets, values: values, payloads: calldatas, salt: _voterBodySalt(descriptionHash)
        });

        // The removal survives the brake and executes, replacing the council.
        assertTrue(_timelock.isOperationPending(operationId));
        skip(_timelock.getMinDelay() + 1);
        _governor.execute({targets: targets, values: values, calldatas: calldatas, descriptionHash: descriptionHash});
        assertEq(_securityCouncil.council(), replacementCouncil);

        // The ousted council is now powerless: its privileged entry points reject it.
        address newImpl = _newImplementation();
        vm.prank(_COUNCIL_MULTISIG);
        vm.expectRevert(
            abi.encodeWithSelector(IXanSecurityCouncil.UnauthorizedCouncil.selector, _COUNCIL_MULTISIG),
            address(_securityCouncil)
        );
        _securityCouncil.scheduleUpgrade(newImpl, "");
    }

    function test_setCouncil_lets_the_voter_body_rotate_the_council() public {
        address newCouncil = makeAddr("newCouncil");

        vm.expectEmit(address(_securityCouncil));
        emit IXanSecurityCouncil.CouncilChanged({previousCouncil: _COUNCIL_MULTISIG, newCouncil: newCouncil});

        vm.prank(address(_timelock));
        _securityCouncil.setCouncil(newCouncil);
        assertEq(_securityCouncil.council(), newCouncil);
    }

    function test_setCouncil_reverts_if_the_caller_is_not_the_timelock() public {
        vm.prank(_COUNCIL_MULTISIG);
        vm.expectRevert(
            abi.encodeWithSelector(IXanSecurityCouncil.UnauthorizedTimelock.selector, _COUNCIL_MULTISIG),
            address(_securityCouncil)
        );
        _securityCouncil.setCouncil(makeAddr("newCouncil"));
    }

    function test_setCouncil_reverts_if_the_new_council_is_the_zero_address() public {
        vm.prank(address(_timelock));
        vm.expectRevert(IXanSecurityCouncil.ZeroCouncilNotAllowed.selector, address(_securityCouncil));
        _securityCouncil.setCouncil(address(0));
    }

    function test_cancelWindow_exceeds_the_voter_cancel_cycle() public view {
        uint256 voterCancelCycle = _governor.votingDelay() + _governor.votingPeriod() + _timelock.getMinDelay();
        assertEq(_securityCouncil.cancelWindow(), voterCancelCycle + Parameters.COUNCIL_CANCEL_BUFFER);
        assertGt(_securityCouncil.cancelWindow(), voterCancelCycle);
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

        vm.prank(_voter);
        uint256 proposalId =
            _governor.propose({targets: targets, values: values, calldatas: calldatas, description: description});

        _warpIntoVotingPeriod();
        vm.prank(_voter);
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
        salt = keccak256(abi.encode("XanSecurityCouncil.upgrade", newImpl, data));
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
