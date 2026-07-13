// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {IXanUpgradeCouncil} from "./interfaces/IXanUpgradeCouncil.sol";

/// @title XanUpgradeCouncil
/// @author Anoma Foundation, 2026
/// @notice The upgrade council's on-chain interface to XAN governance. The timelock is the module's `Ownable` owner
/// and rotates the council multisig via `setCouncil`; the module holds the timelock's `PROPOSER` and `CANCELLER`
/// roles and lets the council:
/// * Schedule XAN token upgrades that the voter body can cancel.
/// * Withdraw its own pending upgrade.
/// It holds no power over voter-body operations.
/// @custom:security-contact security@anoma.foundation
contract XanUpgradeCouncil is IXanUpgradeCouncil, Ownable {
    /// @notice The governor whose voting parameters size the cancel window.
    IGovernor private immutable _GOVERNOR;

    /// @notice The timelock that owns the token and through which upgrades are scheduled, cancelled, and executed.
    TimelockController private immutable _TIMELOCK;

    /// @notice The XAN token proxy that upgrades target.
    address private immutable _TOKEN;

    /// @notice Reaction-time margin added on top of the voter cancel cycle when sizing the cancel window.
    uint256 private immutable _CANCEL_BUFFER;

    /// @notice The council multisig.
    address private _council;

    /// @notice The most recently scheduled council upgrade operation id.
    bytes32 private _pendingOperation;

    /// @notice Thrown when a council-only function is called by another account.
    error UnauthorizedCouncil(address caller);

    /// @notice Thrown when the council schedules an upgrade while one is already pending (one upgrade in flight).
    error UpgradeAlreadyPending(bytes32 operationId);

    /// @notice Thrown when the governor address supplied to the constructor is zero.
    error ZeroGovernorNotAllowed();

    /// @notice Thrown when the token address supplied to the constructor is zero.
    error ZeroTokenNotAllowed();

    /// @notice Thrown when a council address (constructor `initialCouncil` or `setCouncil`) is zero.
    error ZeroCouncilNotAllowed();

    /// @notice Thrown when the implementation address supplied to `scheduleUpgrade` is zero.
    error ZeroImplementationNotAllowed();

    /// @notice Thrown when `cancelUpgrade` is called but no council upgrade is pending in the timelock.
    error NoUpgradePending();

    /// @notice Restricts a function to the council multisig.
    modifier onlyCouncil() {
        require(msg.sender == _council, UnauthorizedCouncil(msg.sender));
        _;
    }

    /// @notice Deploys the module. It must be granted the timelock's `PROPOSER` and `CANCELLER` roles after deployment.
    /// @param governor The governor whose `votingDelay`/`votingPeriod` size the cancel window.
    /// @param timelock The timelock that owns the token (and, as the module's `Ownable` owner, rotates the council).
    /// @param token The XAN token proxy.
    /// @param initialCouncil The initial council multisig.
    /// @param cancelBuffer The reaction-time margin added to the cancel cycle when sizing the cancel window.
    constructor(
        IGovernor governor,
        TimelockController timelock,
        address token,
        address initialCouncil,
        uint256 cancelBuffer
    ) Ownable(address(timelock)) {
        require(address(governor) != address(0), ZeroGovernorNotAllowed());
        require(token != address(0), ZeroTokenNotAllowed());
        require(initialCouncil != address(0), ZeroCouncilNotAllowed());

        _GOVERNOR = governor;
        _TIMELOCK = timelock;
        _TOKEN = token;
        _CANCEL_BUFFER = cancelBuffer;
        _council = initialCouncil;
    }

    /// @inheritdoc IXanUpgradeCouncil
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

    /// @inheritdoc IXanUpgradeCouncil
    /// @dev Callable only by the council. The module only ever aims the timelock's `CANCELLER` role at the operation
    /// it scheduled itself, so the council has no cancel power over voter-body operations.
    function cancelUpgrade() external override onlyCouncil returns (bytes32 operationId) {
        operationId = _pendingOperation;
        require(operationId != bytes32(0) && _TIMELOCK.isOperationPending(operationId), NoUpgradePending());

        emit UpgradeCancelled(operationId);

        _TIMELOCK.cancel(operationId);
    }

    /// @inheritdoc IXanUpgradeCouncil
    /// @dev Callable only by the timelock (the owner), i.e. through a passed voter-body proposal. The council cannot
    /// rotate itself on-chain; a multisig rotates its signers internally without changing its address.
    function setCouncil(address newCouncil) external override onlyOwner {
        require(newCouncil != address(0), ZeroCouncilNotAllowed());

        emit CouncilChanged({previousCouncil: _council, newCouncil: newCouncil});

        _council = newCouncil;
    }

    /// @inheritdoc IXanUpgradeCouncil
    function council() external view override returns (address councilAddress) {
        councilAddress = _council;
    }

    /// @inheritdoc IXanUpgradeCouncil
    function pendingUpgrade() external view override returns (bytes32 operationId) {
        operationId = _pendingOperation;
    }

    /// @inheritdoc IXanUpgradeCouncil
    /// @dev Computed live as `votingDelay + votingPeriod + timelock.getMinDelay() + buffer`, so the window always
    /// exceeds a full voter cancel cycle.
    function cancelWindow() public view override returns (uint256 delay) {
        delay = _GOVERNOR.votingDelay() + _GOVERNOR.votingPeriod() + _TIMELOCK.getMinDelay() + _CANCEL_BUFFER;
    }

    /// @notice Deterministic, council-tagged salt so a council upgrade never collides with a voter-body operation and
    /// can be re-scheduled after a cancel.
    /// @param newImplementation The implementation to upgrade the token to.
    /// @param data The reinitialization calldata forwarded to `upgradeToAndCall`.
    /// @return salt The operation salt.
    function _salt(address newImplementation, bytes calldata data) private pure returns (bytes32 salt) {
        salt = keccak256(abi.encode("XanUpgradeCouncil.upgrade", newImplementation, data));
    }
}
