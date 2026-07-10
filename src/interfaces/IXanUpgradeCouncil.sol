// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

/// @title IXanUpgradeCouncil
/// @author Anoma Foundation, 2026
/// @notice Interface of the upgrade council module.
/// @custom:security-contact security@anoma.foundation
interface IXanUpgradeCouncil {
    /// @notice Emitted when a token upgrade is scheduled in the timelock.
    /// @param newImplementation The implementation the upgrade installs.
    /// @param operationId The scheduled timelock operation id.
    /// @param data The reinitialization calldata forwarded to `upgradeToAndCall`.
    /// @param executableAt The timestamp after which the upgrade becomes executable (the end of the cancel window).
    event UpgradeScheduled(
        address indexed newImplementation, bytes32 indexed operationId, bytes data, uint256 executableAt
    );

    /// @notice Emitted when the council withdraws its own pending upgrade from the timelock.
    /// @param operationId The cancelled timelock operation id.
    event UpgradeCancelled(bytes32 indexed operationId);

    /// @notice Emitted when the council multisig is rotated.
    /// @param previousCouncil The previous council address.
    /// @param newCouncil The new council address.
    event CouncilChanged(address indexed previousCouncil, address indexed newCouncil);

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

    /// @notice Thrown when `renounceOwnership` is called; renouncing is disabled so the voter body always retains the
    /// timelock's ownership lever to rotate the council.
    error RenouncingOwnershipDisabled();

    /// @notice Schedules a token upgrade by scheduling it in the timelock.
    /// @param newImplementation The implementation to upgrade the token to.
    /// @param data The reinitialization calldata forwarded to `upgradeToAndCall` (may be empty).
    /// @return operationId The scheduled timelock operation id.
    function scheduleUpgrade(address newImplementation, bytes calldata data) external returns (bytes32 operationId);

    /// @notice Withdraws the council's own pending upgrade from the timelock. The module can cancel nothing else.
    /// @return operationId The cancelled timelock operation id.
    function cancelUpgrade() external returns (bytes32 operationId);

    /// @notice Rotates the council multisig.
    /// @param newCouncil The new council address.
    function setCouncil(address newCouncil) external;

    /// @notice Returns the current council multisig.
    /// @return councilAddress The council address.
    function council() external view returns (address councilAddress);

    /// @notice Returns the most recently scheduled council upgrade operation id (may already be executed or
    /// cancelled).
    /// @return operationId The tracked operation id.
    function pendingUpgrade() external view returns (bytes32 operationId);

    /// @notice Returns the cancel window: the time a scheduled council upgrade waits in the timelock before it can be
    /// executed.
    /// @return delay The cancel window in seconds.
    function cancelWindow() external view returns (uint256 delay);
}
