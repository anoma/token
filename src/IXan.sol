// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

interface IXan {
    /// @notice Emitted when tokens are locked.
    /// @param owner The owning account.
    /// @param value The number of tokens being locked.
    event Locked(address owner, uint256 value);

    /// @notice Emitted when a vote is cast for a new implementation.
    /// @param voter The voter address.
    /// @param newImplementation The new implementation the vote was cast for.
    /// @param value The number of votes cast.
    event VoteCast(address voter, address newImplementation, uint256 value);

    /// @notice Emitted when a vote is revoked from a new implementation.
    /// @param voter The voting account.
    /// @param newImplementation The new implementation the vote was revoked from.
    /// @param value The number of votes revoked.
    event VoteRevoked(address voter, address newImplementation, uint256 value);

    /// @notice Emitted when the upgrade delay period for a new implementation is started.
    /// @param newImplementation The new implementation for which the delay period was started.
    /// @param startTime The start time.
    /// @param endTime The end time.
    event DelayStarted(address newImplementation, uint48 startTime, uint48 endTime);

    /// @notice Permanently locks tokens for the current implementation until it gets upgraded.
    /// @param value The value to be locked.
    function lock(uint256 value) external;

    /// @notice Casts the vote with the currently locked balance for a new implementation.
    /// An old votum will only get updated if the new locked balance is larger than the old votum.
    /// Otherwise, the function will revert with an error.
    /// @param newImplementation The new implementation to cast the vote for.
    function castVote(address newImplementation) external;

    /// @notice Revokes the vote from a new implementation.
    /// @param newImplementation The new implementation to revoke the vote for.
    function revokeVote(address newImplementation) external;

    /// @notice Starts the delay period if the
    /// @param newImplementation The new implementation to start the delay period for.
    function startDelayPeriod(address newImplementation) external;

    /// @notice Returns the total votes for a new implementation.
    /// @return votes The total votes implementation.
    function totalVotes(address newImplementation) external view returns (uint256 votes);

    /// @notice Returns the most voted implementation.
    /// @return mostVotedNewImplementation The most voted new implementation.
    function mostVotedImplementation() external view returns (address mostVotedNewImplementation);

    /// @notice Checks if the delay period has ended and reverts with errors if not.
    /// @param newImplementation The new implementation to check the delay period for.
    function checkDelayPeriod(address newImplementation) external view;

    /// @notice Checks if the criteria to upgrade to the new implementation are met and reverts with errors if not.
    /// @param newImplementation The new implementation to check the upgrade criteria for.
    function checkUpgradeCriteria(address newImplementation) external view;

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
    /// @return currentImplementation The current implementation.
    function implementation() external view returns (address currentImplementation);

    function DELAY_DURATION() external view returns (uint32 delay);
}
