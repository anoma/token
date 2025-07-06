// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {IXanV1} from "../interfaces/IXanV1.sol";

library Council {
    /// @notice A struct containing data associated with a current implementation and proposed upgrades from it.
    /// @param council The address of the governance council.
    /// @param scheduledUpgrade An upgrade scheduled by the council.
    struct Data {
        address council;
        IXanV1.ScheduledUpgrade scheduledUpgrade;
    }
}
