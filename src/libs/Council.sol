// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

library Council {
    /// @param council The address of the governance council.
    /// @param proposedImpl The proposed implementation to upgrade to.
    /// @param delayEndTime The end time of the delay period.
    struct Data {
        address council;
        address proposedImpl;
        uint48 delayEndTime;
    }
}
