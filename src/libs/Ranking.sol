// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

library Ranking {
    using Ranking for ProposedUpgrades;

    /// @notice A struct containing data associated with a current implementation and proposed upgrades from it.
    /// @param lockedBalances The locked balances associated with the current implementation.
    /// @param lockedTotalSupply The locked total supply associated with the current implementation.
    /// @param ballots The ballots of proposed implementations to upgrade to.
    /// @param ranking The proposed implementations ranking.
    /// @param implCount The count of proposed implementations.
    struct ProposedUpgrades {
        mapping(address owner => uint256) lockedBalances;
        uint256 lockedTotalSupply;
        mapping(address proposedImpl => Ballot) ballots;
        mapping(uint64 rank => address proposedImpl) ranking;
        uint64 implCount;
    }

    /// @notice The vote data of a proposed implementation.
    /// @param vota The vota of the individual voters.
    /// @param totalVotes The total votes casted.
    /// @param rank The voting rank of the implementation
    /// @param  delayEndTime The end time of the delay period.
    /// @param exists Whether the implementation was proposed or not.
    struct Ballot {
        mapping(address voter => uint256 votes) vota;
        uint256 totalVotes;
        uint64 rank;
        uint48 delayEndTime;
        bool exists;
    }

    /// @notice Assigns the highest rank to a proposed implementation.
    /// @param $ The storage containing the proposed upgrades.
    /// @param proposedImpl The proposed implementation to assign the highest rank to.
    function assignWorstRank(ProposedUpgrades storage $, address proposedImpl) internal {
        Ballot storage ballot = $.ballots[proposedImpl];
        ballot.exists = true;
        ballot.rank = $.implCount;

        // Set the highest rank.
        $.ranking[$.implCount] = proposedImpl;
        ++$.implCount;
    }

    /// @notice Bubble the proposed implementation up in the ranking.
    /// @param $ The storage containing the ballots for proposed upgrades.
    /// @param proposedImpl The proposed implementation.
    function bubbleUp(ProposedUpgrades storage $, address proposedImpl) internal {
        Ballot storage ballot = $.ballots[proposedImpl];
        uint64 rank = ballot.rank;
        uint256 votes = ballot.totalVotes;

        uint64 bestRank = 0;

        while (rank > bestRank) {
            uint64 nextBetterRank;
            unchecked {
                nextBetterRank = rank - 1;
            }

            address nextBetterImpl = $.ranking[nextBetterRank];
            uint256 nextBetterVotes = $.ballots[nextBetterImpl].totalVotes;

            if (votes < nextBetterVotes + 1) break;

            _swapRank({$: $, implA: proposedImpl, rankA: rank, implB: nextBetterImpl, rankB: nextBetterRank});
            // Update the cached rank after the swap.
            rank = nextBetterRank;
        }
    }

    /// @notice Bubble the proposed implementation down in the ranking.
    /// @param $ The storage containing the ballots for proposed upgrades.
    /// @param proposedImpl The proposed implementation.
    function bubbleDown(ProposedUpgrades storage $, address proposedImpl) internal {
        Ballot storage ballot = $.ballots[proposedImpl];
        uint64 rank = ballot.rank;
        uint256 votes = ballot.totalVotes;

        uint64 worstRank = $.implCount - 1;

        while (rank < worstRank) {
            uint64 nextWorseRank;
            unchecked {
                nextWorseRank = rank + 1;
            }

            address nextWorseImpl = $.ranking[nextWorseRank];
            uint256 nextWorseVotes = $.ballots[nextWorseImpl].totalVotes;

            if (votes > nextWorseVotes) break;

            _swapRank({$: $, implA: proposedImpl, rankA: rank, implB: nextWorseImpl, rankB: nextWorseRank});

            // Update the cached rank after the swap.
            rank = nextWorseRank;
        }
    }

    /// @notice Swaps the rank of two implementations A and B.
    /// @param $ The storage containing the ballots for proposed upgrades.
    /// @param implA Implementation A.
    /// @param rankA The rank of implementation A before the swap.
    /// @param implB Implementation B.
    /// @param rankB The rank of implementation B before the swap.
    function _swapRank(ProposedUpgrades storage $, address implA, uint64 rankA, address implB, uint64 rankB) private {
        $.ranking[rankA] = implB;
        $.ranking[rankB] = implA;

        $.ballots[implA].rank = rankB;
        $.ballots[implB].rank = rankA;
    }
}
