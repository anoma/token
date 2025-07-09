// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

/// @title Council
/// @author Anoma Foundation, 2025
/// @notice A library containing a data structure to store the governance council address and the data related to the
/// scheduled implementation and delay period end time.
/// @custom:security-contact security@anoma.foundation
library Council {
    /// @notice A struct containing data associated with the governance council.
    /// @param council The address of the governance council.
    /// @param scheduledImpl The scheduled implementation.
    /// @param scheduledEndTime The scheduled end time of the delay period.
    struct Data {
        address council;
        address scheduledImpl;
        uint48 scheduledEndTime;
    }

    /// @notice Returns whether a council upgrade is scheduled or not.
    /// @param data The council data.
    /// @return isScheduled Whether an upgrade is scheduled or not.
    function isUpgradeScheduled(Data storage data) internal view returns (bool isScheduled) {
        isScheduled = data.scheduledImpl != address(0) && data.scheduledEndTime != 0;
    }
}
