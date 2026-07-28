// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

/// @title IXanUpgradeCouncilModule
/// @author Anoma Foundation, 2026
/// @notice Interface of the upgrade council module.
/// @custom:security-contact security@anoma.foundation
interface IXanUpgradeCouncilModule {
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

    /// @notice Schedules a token upgrade by scheduling it in the timelock.
    /// @param newImplementation The implementation to upgrade the token to.
    /// @param data The reinitialization calldata forwarded to `upgradeToAndCall` (may be empty).
    /// @return operationId The scheduled timelock operation id.
    function scheduleUpgrade(address newImplementation, bytes calldata data) external returns (bytes32 operationId);

    /// @notice Withdraws the council's own pending upgrade from the timelock. The module can cancel nothing else.
    /// @return operationId The cancelled timelock operation id.
    function cancelUpgrade() external returns (bytes32 operationId);

    /// @notice Returns the council multisig.
    /// @return council The council address.
    function getCouncil() external view returns (address council);

    /// @notice Returns the timelock that owns the token and through which upgrades are scheduled and cancelled.
    /// @return timelock The timelock address.
    function getTimelock() external view returns (address timelock);

    /// @notice Returns the governor whose voting parameters size the cancel window.
    /// @return governor The governor address.
    function getGovernor() external view returns (address governor);

    /// @notice Returns the XAN token proxy that upgrades target.
    /// @return token The token address.
    function getToken() external view returns (address token);

    /// @notice Returns the reaction-time margin added on top of the voter cancel cycle when sizing the cancel window.
    /// @return cancelBuffer The cancel buffer in seconds.
    function getCancelBuffer() external view returns (uint256 cancelBuffer);

    /// @notice Returns the most recently scheduled council upgrade operation id (may already be executed or
    /// cancelled).
    /// @return operationId The tracked operation id.
    function getPendingUpgradeOperationId() external view returns (bytes32 operationId);

    /// @notice Returns the cancel window: the time a scheduled council upgrade waits in the timelock before it can be
    /// executed.
    /// @return delay The cancel window in seconds.
    function cancelWindow() external view returns (uint256 delay);
}
