// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {IXanUpgradeCouncilModule} from "./interfaces/IXanUpgradeCouncilModule.sol";

/// @title XanUpgradeCouncilModule
/// @author Anoma Foundation, 2026
/// @notice The upgrade council's on-chain interface to XAN governance. The module holds the timelock's `PROPOSER` and
/// `CANCELLER` roles and lets the council:
/// * Schedule a XAN token upgrade that the voter body can cancel.
/// * Withdraw its own pending upgrade.
/// It holds no power over voter-body operations.
/// @custom:security-contact security@anoma.foundation
contract XanUpgradeCouncilModule is IXanUpgradeCouncilModule {
    /// @notice The governor whose voting parameters size the cancel window.
    IGovernor private immutable _GOVERNOR;

    /// @notice The timelock that owns the token and through which upgrades are scheduled, cancelled, and executed.
    TimelockController private immutable _TIMELOCK;

    /// @notice The council multisig that can schedule and cancel upgrade proposals.
    address private immutable _COUNCIL;

    /// @notice The XAN token proxy that upgrades target.
    address private immutable _TOKEN;

    /// @notice Reaction-time margin added on top of the voter cancel cycle when sizing the cancel window.
    uint256 private immutable _CANCEL_BUFFER;

    /// @notice The most recently scheduled council upgrade operation id.
    bytes32 private _pendingUpgradeOperationId;

    /// @notice Thrown when a council-only function is called by another account.
    error UnauthorizedCouncil(address caller);

    /// @notice Thrown when the council schedules an upgrade while one is already pending (one upgrade in flight).
    error UpgradeAlreadyPending(bytes32 operationId);

    /// @notice Thrown when the governor address supplied to the constructor is zero.
    error ZeroGovernorNotAllowed();

    /// @notice Thrown when the timelock address supplied to the constructor is zero.
    error ZeroTimelockNotAllowed();

    /// @notice Thrown when the token address supplied to the constructor is zero.
    error ZeroTokenNotAllowed();

    /// @notice Thrown when the council address supplied to the constructor is zero.
    error ZeroCouncilNotAllowed();

    /// @notice Thrown when the implementation address supplied to `scheduleUpgrade` is zero.
    error ZeroImplementationNotAllowed();

    /// @notice Thrown when `cancelUpgrade` is called but no council upgrade is pending in the timelock.
    error NoUpgradePending();

    /// @notice Restricts a function to the council multisig.
    modifier onlyCouncil() {
        _checkCouncil();
        _;
    }

    /// @notice Deploys the module. It must be granted the timelock's `PROPOSER` and `CANCELLER` roles after deployment.
    /// @param governor The governor whose `votingDelay`/`votingPeriod` size the cancel window.
    /// @param timelock The timelock that owns the token and through which upgrades are scheduled and cancelled.
    /// @param council The council multisig.
    /// @param token The XAN token proxy.
    /// @param cancelBuffer The reaction-time margin added to the cancel cycle when sizing the cancel window.
    constructor(IGovernor governor, TimelockController timelock, address council, address token, uint256 cancelBuffer) {
        require(address(governor) != address(0), ZeroGovernorNotAllowed());
        require(address(timelock) != address(0), ZeroTimelockNotAllowed());
        require(council != address(0), ZeroCouncilNotAllowed());
        require(token != address(0), ZeroTokenNotAllowed());

        _GOVERNOR = governor;
        _TIMELOCK = timelock;
        _COUNCIL = council;
        _TOKEN = token;
        _CANCEL_BUFFER = cancelBuffer;
    }

    /// @inheritdoc IXanUpgradeCouncilModule
    /// @dev Callable only by the council. The delay is sized (see `cancelWindow`) to leave a full voter cancel cycle.
    /// Only one council upgrade may be pending at a time.
    function scheduleUpgrade(address newImplementation, bytes calldata data)
        external
        override
        onlyCouncil
        returns (bytes32 operationId)
    {
        require(newImplementation != address(0), ZeroImplementationNotAllowed());
        // One council upgrade in flight at a time.
        require(
            _pendingUpgradeOperationId == bytes32(0) || !_TIMELOCK.isOperationPending(_pendingUpgradeOperationId),
            UpgradeAlreadyPending(_pendingUpgradeOperationId)
        );

        bytes memory call = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (newImplementation, data));
        bytes32 salt = _salt(newImplementation, data);
        uint256 delay = cancelWindow();

        operationId =
            _TIMELOCK.hashOperation({target: _TOKEN, value: 0, data: call, predecessor: bytes32(0), salt: salt});
        _pendingUpgradeOperationId = operationId;

        emit UpgradeScheduled(newImplementation, operationId, data, block.timestamp + delay);

        _TIMELOCK.schedule({target: _TOKEN, value: 0, data: call, predecessor: bytes32(0), salt: salt, delay: delay});
    }

    /// @inheritdoc IXanUpgradeCouncilModule
    /// @dev Callable only by the council. The module only ever aims the timelock's `CANCELLER` role at the operation
    /// it scheduled itself, so the council has no cancel power over voter-body operations.
    function cancelUpgrade() external override onlyCouncil returns (bytes32 operationId) {
        operationId = _pendingUpgradeOperationId;
        require(operationId != bytes32(0) && _TIMELOCK.isOperationPending(operationId), NoUpgradePending());

        emit UpgradeCancelled(operationId);

        _TIMELOCK.cancel(operationId);
    }

    /// @inheritdoc IXanUpgradeCouncilModule
    function getCouncil() external view override returns (address council) {
        council = _COUNCIL;
    }

    /// @inheritdoc IXanUpgradeCouncilModule
    function getTimelock() external view override returns (address timelock) {
        timelock = address(_TIMELOCK);
    }

    /// @inheritdoc IXanUpgradeCouncilModule
    function getPendingUpgradeOperationId() external view override returns (bytes32 operationId) {
        operationId = _pendingUpgradeOperationId;
    }

    /// @inheritdoc IXanUpgradeCouncilModule
    /// @dev Computed live as `votingDelay + votingPeriod + timelock.getMinDelay() + buffer`, so the window always
    /// exceeds a full voter cancel cycle.
    function cancelWindow() public view override returns (uint256 delay) {
        delay = _GOVERNOR.votingDelay() + _GOVERNOR.votingPeriod() + _TIMELOCK.getMinDelay() + _CANCEL_BUFFER;
    }

    /// @notice Checks that the caller is the council.
    function _checkCouncil() internal view {
        require(_COUNCIL == msg.sender, UnauthorizedCouncil({caller: msg.sender}));
    }

    /// @notice Deterministic, council-tagged salt so a council upgrade never collides with a voter-body operation and
    /// can be re-scheduled after a cancel.
    /// @param newImplementation The implementation to upgrade the token to.
    /// @param data The reinitialization calldata forwarded to `upgradeToAndCall`.
    /// @return salt The operation salt.
    function _salt(address newImplementation, bytes calldata data) private pure returns (bytes32 salt) {
        salt = keccak256(abi.encode("XanUpgradeCouncilModule.upgrade", newImplementation, data));
    }
}
