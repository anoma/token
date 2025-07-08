// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

/// @title Locking
/// @author Anoma Foundation, 2025
/// @notice A library containing data structures and methods related to and ranking.
/// @custom:security-contact security@anoma.foundation
library Voting {
    /// @notice A struct containing data associated with the voter body.
    /// @param ballots The ballots of proposed implementations to upgrade to.
    /// @param mostVotedImpl The most voted implementation.
    /// @param scheduledImpl The scheduled implementation.
    /// @param scheduledEndTime The scheduled end time of the delay period.
    struct Data {
        mapping(address proposedImpl => Ballot) ballots;
        address mostVotedImpl;
        address scheduledImpl;
        uint48 scheduledEndTime;
    }

    /// @notice The vote data of a proposed implementation.
    /// @param vota The vota of the individual identities.
    /// @param totalVotes The total votes casted.
    /// @param rank The voting rank of the implementation
    /// @param exists Whether the implementation was proposed or not.
    struct Ballot {
        mapping(address voter => uint256 votes) vota;
        uint256 totalVotes;
        uint48 rank;
        bool exists;
    }
}
