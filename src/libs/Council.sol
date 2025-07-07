// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

/// @title Council
/// @author TODO, 2025
/// @notice A library containing a data structure to store the governance council address and the data related to the
/// scheduled implementation and delay period end time.
/// @custom:security-contact TODO
library Council {
    /// @notice A struct containing data associated with a current implementation and proposed upgrades from it.
    /// @param council The address of the governance council.
    /// @param scheduledImpl The scheduled implementation.
    /// @param scheduledEndTime The scheduled end time of the delay period.
    struct Data {
        address council;
        address scheduledImpl;
        uint48 scheduledEndTime;
    }
}
