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

    /// @notice Updates the rank of implementations being ranked lower (better) or higher (worse)
    /// than the proposed implementation.
    /// @param $ The storage containing the ballots for proposed upgrades.
    /// @param proposedImpl The proposed implementation.
    /// @param direction The search direction.
    function updateRanking(ProposedUpgrades storage $, address proposedImpl, SearchDirection direction) internal {
        uint64 proposedImplRank = $.ballots[proposedImpl].rank;
        uint256 proposedImplVotes = $.ballots[proposedImpl].totalVotes;

        // Set variables depending on the search direction.
        uint64 limitRank;
        function(uint64, uint64) pure returns (bool) compareRanks;
        function(uint256, uint256) pure returns (bool) compareVotes;

        if (direction == SearchDirection.Lower) {
            limitRank = 0;
            compareRanks = _gtUint64;
            compareVotes = _gtUint256;
        } else {
            limitRank = $.implCount - 1;
            compareRanks = _ltUint64;
            compareVotes = _leUint256;
        }

        /**
         * Check if the rank of the proposed implementation deviates from the limit. We distinguish two cases:
         * 1. Case `SearchDirection.Lower`:
         *    - Checks if `proposedImplRank > limitRank` (where `limitRank = 0`)
         *      and eventually must be ranked lower (better).
         * 2. Case `SearchDirection.Higher`:
         *    - Checks if `proposedImplRank < limitRank` (where `limitRank = highestRank`)
         *      and eventually must be ranked higher (worse).
         */
        if (compareRanks(proposedImplRank, limitRank)) {
            // Cache the rank, address, and votes of the next higher/lower ranked implementation.
            uint64 nextRank = direction == SearchDirection.Lower ? proposedImplRank - 1 : proposedImplRank + 1;
            (address nextImpl, uint256 nextVotes) = _getImplAndVotes($, nextRank);

            // Check if the next lower/higher ranked implementation has more/less votes.
            while (compareVotes(proposedImplVotes, nextVotes)) {
                // Switch the ranks.
                _swapRank({$: $, implA: proposedImpl, rankA: proposedImplRank, implB: nextImpl, rankB: nextRank});

                // Update the rank of the proposed implementation.
                proposedImplRank = nextRank;

                // Update the rank, address, and votes of the next higher/lower ranked implementation.
                if (compareRanks(proposedImplRank, limitRank)) {
                    direction == SearchDirection.Lower ? --nextRank : ++nextRank;
                    (nextImpl, nextVotes) = _getImplAndVotes($, nextRank);
                } else {
                    break;
                }
            }
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

    /// @notice Greater than comparator function for `uint64` types.
    /// @param lhs The left-hand side value.
    /// @param rhs The right-hand side value.
    /// @param isGreaterThan Whether the left- is greater than the right-hand side.
    function _gtUint64(uint64 lhs, uint64 rhs) private pure returns (bool isGreaterThan) {
        isGreaterThan = lhs > rhs;
    }

    /// @notice Less than comparator function for `uint64` types.
    /// @param lhs The left-hand side value.
    /// @param rhs The right-hand side value.
    /// @param isLessThan Whether the left- is less than the right-hand side.
    function _ltUint64(uint64 lhs, uint64 rhs) private pure returns (bool isLessThan) {
        isLessThan = lhs < rhs;
    }

    /// @notice Greater than comparator function for `uint256` types.
    /// @param lhs The left-hand side value.
    /// @param rhs The right-hand side value.
    /// @param isGreaterThan Whether the left- is greater than the right-hand side.
    function _gtUint256(uint256 lhs, uint256 rhs) private pure returns (bool isGreaterThan) {
        isGreaterThan = lhs > rhs;
    }

    /// @notice Less than or equal comparator function for `uint256` types.
    /// @param lhs The left-hand side value.
    /// @param rhs The right-hand side value.
    /// @param isLessThanOrEqual Whether the left- is less than or Equal the right-hand side.
    function _leUint256(uint256 lhs, uint256 rhs) private pure returns (bool isLessThanOrEqual) {
        isLessThanOrEqual = lhs < rhs + 1;
    }
}
