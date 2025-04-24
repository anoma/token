// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

interface IXanV1 {
    /// @notice Emitted when tokens are locked.
    /// @param owner The owning account.
    /// @param value The number of tokens being locked.
    event Locked(address owner, uint256 value);

    /// @notice Emitted when a vote is cast for a implementation.
    /// @param voter The voter address.
    /// @param implementation The implementation the vote was cast for.
    /// @param value The number of votes cast.
    event VoteCast(address voter, address implementation, uint256 value);

    /// @notice Emitted when a vote is revoked from a new implementation.
    /// @param voter The voting account.
    /// @param implementation The implementation the vote was revoked from.
    /// @param value The number of votes revoked.
    event VoteRevoked(address voter, address implementation, uint256 value);

    /// @notice Emitted when the upgrade delay period for a new implementation is started.
    /// @param implementation The implementation for which the delay period was started.
    /// @param startTime The start time.
    /// @param endTime The end time.
    event DelayStarted(address implementation, uint48 startTime, uint48 endTime);

    /// @notice Permanently locks tokens for the current implementation until it gets upgraded.
    /// @param value The value to be locked.
    function lock(uint256 value) external;

    /// @notice Transfers tokens and immediately locks them.
    /// @param to The receiver.
    /// @param value The value to be transferred and locked.
    function transferAndLock(address to, uint256 value) external;

    /// @notice Casts the vote with the currently locked balance for a new implementation.
    /// An old votum will only get updated if the new locked balance is larger than the old votum.
    /// Otherwise, the function will revert with an error.
    /// @param proposedImpl The proposed implementation to cast the vote for.
    function castVote(address proposedImpl) external;

    /// @notice Revokes the vote from a new implementation.
    /// @param proposedImpl The proposed implementation to revoke the vote for.
    function revokeVote(address proposedImpl) external;

    /// @notice Starts the delay period if the
    /// @param proposedImpl The proposed implementation to start the delay period for.
    function startDelayPeriod(address proposedImpl) external;

    /// @notice Returns the total votes for a new implementation.
    /// @return votes The total votes implementation.
    function totalVotes(address proposedImpl) external view returns (uint256 votes);

    /// @notice Returns the unlocked token balance of an account.
    /// @param from The account to query.
    /// @param unlockedBalance The unlocked balance.
    function unlockedBalanceOf(address from) external view returns (uint256 unlockedBalance);

    /// @notice Returns the locked token balance of an account.
    /// @param from The account to query.
    /// @param lockedBalance The locked balance.
    function lockedBalanceOf(address from) external view returns (uint256 lockedBalance);

    /// @notice Returns the locked total supply of the token.
    /// @param lockedSupply The locked supply.
    function lockedTotalSupply() external view returns (uint256 lockedSupply);

    /// @notice Returns the current implementation
    /// @return current The current implementation.
    function implementation() external view returns (address current);

    /// @notice Returns the proposed implementation with the respective rank.
    /// @return rankedImplementation The proposed implementation with the respective rank.
    function proposedImplementationByRank(uint64 rank) external view returns (address rankedImplementation);
}
