// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {IXanV1} from "../interfaces/IXanV1.sol";

library Voting {
    using Voting for Data;

    /// @notice A struct containing data associated with a current implementation and proposed upgrades from it.
    /// @param ballots The ballots of proposed implementations to upgrade to.
    /// @param ranking The proposed implementations ranking.
    /// @param implCount The count of proposed implementations.
    /// @param scheduledImpl The scheduled implementation.
    /// @param scheduledEndTime The scheduled end time of the delay period.
    struct Data {
        mapping(address proposedImpl => Ballot) ballots;
        mapping(uint48 rank => address proposedImpl) ranking;
        uint48 implCount;
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

    /// @notice Assigns the highest rank to a proposed implementation.
    /// @param data The voting data containing the proposed upgrades.
    /// @param proposedImpl The proposed implementation to assign the highest rank to.
    function assignWorstRank(Data storage data, address proposedImpl) internal {
        Ballot storage ballot = data.ballots[proposedImpl];
        ballot.exists = true;
        ballot.rank = data.implCount;

        // Set the worst rank.
        data.ranking[data.implCount] = proposedImpl;
        ++data.implCount;
    }

    /// @notice Bubble the proposed implementation up in the ranking.
    /// @param data The voting data containing the ballots for proposed upgrades.
    /// @param proposedImpl The proposed implementation.
    function bubbleUp(Data storage data, address proposedImpl) internal {
        Ballot storage ballot = data.ballots[proposedImpl];
        uint48 rank = ballot.rank;
        uint256 votes = ballot.totalVotes;

        uint48 bestRank = 0;

        while (rank > bestRank) {
            uint48 nextBetterRank;
            unchecked {
                nextBetterRank = rank - 1;
            }

            address nextBetterImpl = data.ranking[nextBetterRank];
            uint256 nextBetterVotes = data.ballots[nextBetterImpl].totalVotes;

            if (votes < nextBetterVotes + 1) break;

            _swapRank({data: data, implA: proposedImpl, rankA: rank, implB: nextBetterImpl, rankB: nextBetterRank});
            // Update the cached rank after the swap.
            rank = nextBetterRank;
        }
    }

    /// @notice Bubble the proposed implementation down in the ranking.
    /// @param data The voting data containing the ballots for proposed upgrades.
    /// @param proposedImpl The proposed implementation.
    function bubbleDown(Data storage data, address proposedImpl) internal {
        Ballot storage ballot = data.ballots[proposedImpl];
        uint48 rank = ballot.rank;
        uint256 votes = ballot.totalVotes;

        uint48 worstRank = data.implCount - 1;

        while (rank < worstRank) {
            uint48 nextWorseRank;
            unchecked {
                nextWorseRank = rank + 1;
            }

            address nextWorseImpl = data.ranking[nextWorseRank];
            uint256 nextWorseVotes = data.ballots[nextWorseImpl].totalVotes;

            if (votes > nextWorseVotes) break;

            _swapRank({data: data, implA: proposedImpl, rankA: rank, implB: nextWorseImpl, rankB: nextWorseRank});

            // Update the cached rank after the swap.
            rank = nextWorseRank;
        }
    }

    /// @notice Swaps the rank of two implementations A and B.
    /// @param data The storage containing the ballots for proposed upgrades.
    /// @param implA Implementation A.
    /// @param rankA The rank of implementation A before the swap.
    /// @param implB Implementation B.
    /// @param rankB The rank of implementation B before the swap.
    function _swapRank(Data storage data, address implA, uint48 rankA, address implB, uint48 rankB) private {
        data.ranking[rankA] = implB;
        data.ranking[rankB] = implA;

        data.ballots[implA].rank = rankB;
        data.ballots[implB].rank = rankA;
    }

    /// @notice Returns the implementation with the respective rank or `address(0)` if the rank does not exist.
    /// @param rank The rank to return the implementation for.
    /// @return impl The proposed implementation with the respective rank or `address(0)` if the rank does not exist.
    function implementationByRank(Data storage data, uint48 rank) internal view returns (address impl) {
        uint48 implCount = data.implCount;

        if (implCount == 0 || rank > implCount - 1) {
            return impl = address(0);
        }

        impl = data.ranking[rank];
    }
}
