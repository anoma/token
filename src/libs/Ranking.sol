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

    /// @notice The search direction to be used when updating the implementation ranking.
    /// @param Lower Used when a vote is casted for an implementation that might result in a lower (better) ranking.
    /// @param Higher Used when a vote is revoked from an implementation that might result in a higher (worse) ranking.
    enum SearchDirection {
        Lower,
        Higher
    }

    /// @notice Assigns the highest rank to a proposed implementation.
    /// @param $ The storage containing the proposed upgrades.
    /// @param proposedImpl The proposed implementation to assign the highest rank to.
    function assignHighestRank(ProposedUpgrades storage $, address proposedImpl) internal {
        $.ballots[proposedImpl].exists = true;
        $.ballots[proposedImpl].rank = $.implCount;

        // Set the highest rank.
        uint64 highestRank = $.implCount;
        $.ranking[highestRank] = proposedImpl;
        ++$.implCount;
    }

    /// @notice Updates the rank of the proposed implementation and those being ranked lower (better).
    /// @param $ The storage containing the ballots for proposed upgrades.
    /// @param proposedImpl The proposed implementation.
    function updateLowerRanked(ProposedUpgrades storage $, address proposedImpl) internal {
        uint64 rank = $.ballots[proposedImpl].rank;
        uint256 votes = $.ballots[proposedImpl].totalVotes;

        while (rank > 0) {
            uint64 lowerRank = rank - 1;
            (address lowerImpl, uint256 lowerVotes) = _getImplAndVotes($, lowerRank);

            if (votes <= lowerVotes) break;

            _swapRank({$: $, implA: proposedImpl, rankA: rank, implB: lowerImpl, rankB: lowerRank});
            rank = lowerRank;
        }
    }

    /// @notice Updates the rank of the proposed implementation and those being ranked higher (worse).
    /// @param $ The storage containing the ballots for proposed upgrades.
    /// @param proposedImpl The proposed implementation.
    function updateHigherRanked(ProposedUpgrades storage $, address proposedImpl) internal {
        uint64 rank = $.ballots[proposedImpl].rank;
        uint256 votes = $.ballots[proposedImpl].totalVotes;
        uint64 maxRank = $.implCount - 1;

        while (rank < maxRank) {
            uint64 higherRank = rank + 1;
            (address higherImpl, uint256 higherVotes) = _getImplAndVotes($, higherRank);

            if (votes > higherVotes) break;

            _swapRank({$: $, implA: proposedImpl, rankA: rank, implB: higherImpl, rankB: higherRank});
            rank = higherRank;
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

    /// @notice Returns the implementation and associated votes for a specific rank.
    /// @param $ The storage containing the ballots for proposed upgrades.
    /// @param rank The rank to return the implementation and votes for.
    /// @return impl The implementation for the specific rank.
    /// @return votes The votes for the specific rank.
    function _getImplAndVotes(ProposedUpgrades storage $, uint64 rank)
        private
        view
        returns (address impl, uint256 votes)
    {
        impl = $.ranking[rank];
        votes = $.ballots[impl].totalVotes;
    }
}
