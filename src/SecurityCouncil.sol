// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {ISecurityCouncil} from "./interfaces/ISecurityCouncil.sol";

/// @title SecurityCouncil
/// @author Anoma Foundation, 2026
/// @notice The security council's on-chain interface to XAN governance. This module
/// holds the timelock's `PROPOSER` and `CANCELLER` roles and has the power to:
/// * Propose XAN token upgrades that the voter body can cancel.
/// * Cancel proposals by the XAN voter body in the timelock.
/// @custom:security-contact security@anoma.foundation
contract SecurityCouncil is ISecurityCouncil {
    /// @notice The governor whose voting parameters size the cancel window.
    IGovernor private immutable _GOVERNOR;

    /// @notice The timelock that owns the token and through which upgrades are scheduled, cancelled, and executed.
    TimelockController private immutable _TIMELOCK;

    /// @notice The XAN token proxy that upgrades target.
    address private immutable _TOKEN;

    /// @notice Reaction-time margin added on top of the voter cancel cycle when sizing the cancel window.
    uint256 private immutable _CANCEL_BUFFER;

    /// @notice The security council multisig.
    address private _council;

    /// @notice The most recently scheduled council upgrade operation id.
    bytes32 private _pendingOperation;

    /// @notice Restricts a function to the council multisig.
    modifier onlyCouncil() {
        require(msg.sender == _council, UnauthorizedCouncil(msg.sender));
        _;
    }

    /// @notice Restricts a function to the timelock (i.e. a passed governance proposal executed by the voter body).
    modifier onlyTimelock() {
        require(msg.sender == address(_TIMELOCK), UnauthorizedTimelock(msg.sender));
        _;
    }

    /// @notice Deploys the module. It must be granted the timelock's `PROPOSER` and `CANCELLER` roles after deployment.
    /// @param governor The governor whose `votingDelay`/`votingPeriod` size the cancel window.
    /// @param timelock The timelock that owns the token.
    /// @param token The XAN token proxy.
    /// @param initialCouncil The initial council multisig.
    /// @param cancelBuffer The reaction-time margin added to the cancel cycle when sizing the cancel window.
    constructor(
        IGovernor governor,
        TimelockController timelock,
        address token,
        address initialCouncil,
        uint256 cancelBuffer
    ) {
        require(address(governor) != address(0), ZeroGovernorNotAllowed());
        require(address(timelock) != address(0), ZeroTimelockNotAllowed());
        require(token != address(0), ZeroTokenNotAllowed());
        require(initialCouncil != address(0), ZeroCouncilNotAllowed());

        _GOVERNOR = governor;
        _TIMELOCK = timelock;
        _TOKEN = token;
        _council = initialCouncil;
        _CANCEL_BUFFER = cancelBuffer;
    }

    /// @inheritdoc ISecurityCouncil
    /// @dev The delay is sized (see `cancelWindow`) to leave a full voter cancel cycle. Only one council upgrade may be
    /// pending at a time.
    function scheduleUpgrade(address newImplementation, bytes calldata data)
        external
        override
        onlyCouncil
        returns (bytes32 operationId)
    {
        require(newImplementation != address(0), ZeroImplementationNotAllowed());
        // One council upgrade in flight at a time.
        require(
            _pendingOperation == bytes32(0) || !_TIMELOCK.isOperationPending(_pendingOperation),
            UpgradeAlreadyPending(_pendingOperation)
        );

        bytes memory call = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (newImplementation, data));
        bytes32 salt = _salt(newImplementation, data);
        uint256 delay = cancelWindow();

        operationId =
            _TIMELOCK.hashOperation({target: _TOKEN, value: 0, data: call, predecessor: bytes32(0), salt: salt});
        _pendingOperation = operationId;

        emit UpgradeScheduled(newImplementation, operationId, data, block.timestamp + delay);

        _TIMELOCK.schedule({target: _TOKEN, value: 0, data: call, predecessor: bytes32(0), salt: salt, delay: delay});
    }

    /// @inheritdoc ISecurityCouncil
    function cancelCouncilUpgrade() external override onlyCouncil returns (bytes32 operationId) {
        operationId = _pendingOperation;
        require(operationId != bytes32(0), NoUpgradeScheduled());
        require(_TIMELOCK.isOperationPending(operationId), UpgradeNotPending());

        emit CouncilUpgradeCancelled(operationId, msg.sender);

        _TIMELOCK.cancel(operationId);
    }

    /// @inheritdoc ISecurityCouncil
    function cancel(address[] calldata targets, uint256[] calldata values, bytes[] calldata payloads, bytes32 salt)
        external
        override
        onlyCouncil
        returns (bytes32 operationId)
    {
        // The voter body's power to replace the council (`setCouncil`) must survive the council's brake; otherwise a
        // captured council could veto its own removal indefinitely. A standalone `setCouncil` call is therefore the one
        // operation the council may not cancel. Bundling it with anything else (length != 1) stays cancellable, so a
        // malicious upgrade cannot ride along under this exemption.
        require(
            !(targets.length == 1 && targets[0] == address(this) && bytes4(payloads[0]) == this.setCouncil.selector),
            CannotCancelCouncilRotation()
        );

        operationId = _TIMELOCK.hashOperationBatch({
            targets: targets, values: values, payloads: payloads, predecessor: bytes32(0), salt: salt
        });

        emit ProposalCancelled(operationId);

        _TIMELOCK.cancel(operationId);
    }

    /// @inheritdoc ISecurityCouncil
    function setCouncil(address newCouncil) external override onlyTimelock {
        require(newCouncil != address(0), ZeroCouncilNotAllowed());
        emit CouncilChanged(_council, newCouncil);
        _council = newCouncil;
    }

    /// @inheritdoc ISecurityCouncil
    function council() external view override returns (address councilAddress) {
        councilAddress = _council;
    }

    /// @inheritdoc ISecurityCouncil
    function pendingUpgrade() external view override returns (bytes32 operationId) {
        operationId = _pendingOperation;
    }

    /// @inheritdoc ISecurityCouncil
    function cancelWindow() public view override returns (uint256 delay) {
        delay = _GOVERNOR.votingDelay() + _GOVERNOR.votingPeriod() + _TIMELOCK.getMinDelay() + _CANCEL_BUFFER;
    }

    /// @notice Deterministic, council-tagged salt so a council upgrade never collides with a voter-body operation and
    /// can be re-scheduled after a cancel.
    /// @param newImplementation The implementation to upgrade the token to.
    /// @param data The reinitialization calldata forwarded to `upgradeToAndCall`.
    /// @return salt The operation salt.
    function _salt(address newImplementation, bytes calldata data) private pure returns (bytes32 salt) {
        salt = keccak256(abi.encode("SecurityCouncil.upgrade", newImplementation, data));
    }
}
