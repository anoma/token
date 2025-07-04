// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

library Council {
    struct ProposedUpgrade {
        mapping(address voter => uint256 votes) vota;
        uint256 totalVetoVotes;
        uint48 delayEndTime;
        address proposedImpl;
    }
}
