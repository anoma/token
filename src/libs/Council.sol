// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

library Council {
    struct ProposedUpgrade {
        address proposedImpl;
        uint48 delayEndTime;
    }
}
