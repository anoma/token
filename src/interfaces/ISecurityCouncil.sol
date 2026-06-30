// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

/// @title ISecurityCouncil
/// @author Anoma Foundation, 2026
/// @notice Interface of the security council module.
/// @custom:security-contact security@anoma.foundation
interface ISecurityCouncil {
    /// @notice Emitted when the council schedules a token upgrade in the timelock.
    /// @param newImplementation The implementation the upgrade installs.
    /// @param operationId The scheduled timelock operation id.
    /// @param data The reinitialization calldata forwarded to `upgradeToAndCall`.
    /// @param executableAt The timestamp after which the upgrade becomes executable (the end of the cancel window).
    event UpgradeScheduled(
        address indexed newImplementation, bytes32 indexed operationId, bytes data, uint256 executableAt
    );

    /// @notice Emitted when the council cancels a queued governance operation in the timelock.
    /// @param operationId The cancelled timelock operation id.
    event ProposalCancelled(bytes32 indexed operationId);

    /// @notice Emitted when the council address is rotated by the voter body (through the timelock).
    /// @param previousCouncil The previous council address.
    /// @param newCouncil The new council address.
    event CouncilChanged(address indexed previousCouncil, address indexed newCouncil);

    /// @notice Thrown when a council-only function is called by another account.
    error UnauthorizedCouncil(address caller);

    /// @notice Thrown when a timelock-only function is called by another account.
    error UnauthorizedTimelock(address caller);

    /// @notice Thrown when the council schedules an upgrade while one is already pending (one upgrade in flight).
    error UpgradeAlreadyPending(bytes32 operationId);

    /// @notice Thrown when the governor address supplied to the constructor is zero.
    error ZeroGovernorNotAllowed();

    /// @notice Thrown when the timelock address supplied to the constructor is zero.
    error ZeroTimelockNotAllowed();

    /// @notice Thrown when the token address supplied to the constructor is zero.
    error ZeroTokenNotAllowed();

    /// @notice Thrown when a council address (constructor `initialCouncil` or `setCouncil`) is zero.
    error ZeroCouncilNotAllowed();

    /// @notice Thrown when the implementation address supplied to `scheduleUpgrade` is zero.
    error ZeroImplementationNotAllowed();

    /// @notice Thrown when the council attempts to cancel a standalone `setCouncil` rotation, which would let a
    /// captured council veto its own replacement.
    error CannotCancelCouncilRotation();

    /// @notice Schedules a token upgrade by scheduling it in the timelock.
    /// @param newImplementation The implementation to upgrade the token to.
    /// @param data The reinitialization calldata forwarded to `upgradeToAndCall` (may be empty).
    /// @return operationId The scheduled timelock operation id.
    function scheduleUpgrade(address newImplementation, bytes calldata data) external returns (bytes32 operationId);

    /// @notice Cancels a queued single-call operation in the timelock.
    /// @param target The address the operation calls.
    /// @param value The native token value forwarded with the call.
    /// @param data The calldata of the call.
    /// @param salt The operation salt (read from the timelock's `CallSalt` event).
    /// @return operationId The cancelled timelock operation id.
    function cancel(address target, uint256 value, bytes calldata data, bytes32 salt)
        external
        returns (bytes32 operationId);

    /// @notice Cancels a queued batch operation in the timelock.
    /// @param targets The addresses the operation calls.
    /// @param values The native token values forwarded with each call.
    /// @param payloads The calldata of each call.
    /// @param salt The operation salt (read from the timelock's `CallSalt` event).
    /// @return operationId The cancelled timelock operation id.
    function cancelBatch(address[] calldata targets, uint256[] calldata values, bytes[] calldata payloads, bytes32 salt)
        external
        returns (bytes32 operationId);

    /// @notice Rotates the council address. Callable only by the timelock (a passed governance proposal), so the voter
    /// body can replace a captured or inactive council.
    /// @param newCouncil The new council address.
    function setCouncil(address newCouncil) external;

    /// @notice Returns the current council address.
    /// @return councilAddress The council address.
    function council() external view returns (address councilAddress);

    /// @notice Returns the most recently scheduled council upgrade operation id (may already be executed or
    /// cancelled).
    /// @return operationId The tracked operation id.
    function pendingUpgrade() external view returns (bytes32 operationId);

    /// @notice Returns the cancel window, computed live as
    /// `votingDelay + votingPeriod + timelock.getMinDelay() + buffer`, so it always exceeds a full voter cancel cycle.
    /// @return delay The cancel window in seconds.
    function cancelWindow() external view returns (uint256 delay);
}
