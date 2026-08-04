// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

/// @title IXanUpgradeCouncilModule
/// @author Anoma Foundation, 2026
/// @notice Interface of the upgrade council module.
/// @custom:security-contact security@anoma.foundation
interface IXanUpgradeCouncilModule {
    /// @notice Emitted when a token upgrade is scheduled in the timelock.
    /// @param newImplementation The implementation the upgrade installs.
    /// @param data The reinitialization calldata forwarded to `upgradeToAndCall`.
    /// @param operationId The scheduled timelock operation id.
    /// @param scheduledAt The timestamp the upgrade was scheduled at, which the execution gate measures its delay from.
    /// @param earliestExecutableAt The earliest timestamp the upgrade can execute; a later settings raise pushes the
    /// actual moment out, nothing moves it in.
    event UpgradeScheduled(
        address indexed newImplementation,
        bytes data,
        bytes32 indexed operationId,
        uint48 scheduledAt,
        uint256 earliestExecutableAt
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

    /// @notice Checks that an upgrade delay computed from the current settings has elapsed since `scheduledAt`.
    /// @param scheduledAt The timestamp the upgrade was scheduled at.
    function checkUpgradeDelayElapsed(uint48 scheduledAt) external view;

    /// @notice Returns the delay a scheduled council upgrade waits out before anyone can execute it. It exceeds a
    /// full voter-cancel cycle, so the voter body can always cancel the upgrade first.
    /// @return delay The upgrade delay in seconds.
    function upgradeDelay() external view returns (uint256 delay);

    /// @notice Returns the margin added on top of the voter cancel cycle when sizing the upgrade delay.
    /// @return extraDelay The extra delay in seconds.
    function getExtraDelay() external view returns (uint256 extraDelay);

    /// @notice Returns the council multisig.
    /// @return council The council address.
    function getCouncil() external view returns (address council);

    /// @notice Returns the timelock that owns the token and through which upgrades are scheduled and cancelled.
    /// @return timelock The timelock address.
    function getTimelock() external view returns (address timelock);

    /// @notice Returns the governor whose voting parameters size the upgrade delay.
    /// @return governor The governor address.
    function getGovernor() external view returns (address governor);

    /// @notice Returns the XAN token proxy that upgrades target.
    /// @return token The token address.
    function getToken() external view returns (address token);

    /// @notice Returns the most recently scheduled council upgrade operation id (may already be executed or
    /// cancelled).
    /// @return operationId The last scheduled upgrade operation id, or zero if no council upgrade was ever scheduled.
    function getLastScheduledUpgradeOperationId() external view returns (bytes32 operationId);
}
