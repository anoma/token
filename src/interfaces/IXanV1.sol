// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

interface IXanV1 {
    /// @notice Emitted when tokens are locked.
    /// @param account The owning account.
    /// @param value The number of tokens being locked.
    event Locked(address indexed account, uint256 value);

    /// @notice Emitted when a vote is cast for a implementation.
    /// @param voter The voter address.
    /// @param implementation The implementation the vote was cast for.
    /// @param value The number of votes cast.
    event VoteCast(address indexed voter, address indexed implementation, uint256 value);

    /// @notice Emitted when a vote is revoked from a new implementation.
    /// @param voter The voting account.
    /// @param implementation The implementation the vote was revoked from.
    /// @param value The number of votes revoked.
    event VoteRevoked(address indexed voter, address indexed implementation, uint256 value);

    /// @notice Emitted when the upgrade delay period for a new implementation proposed by the voter body is started.
    /// @param implementation The implementation the delay is started for.
    /// @param startTime The start time.
    /// @param endTime The end time.
    event VoterBodyUpgradeDelayStarted(address indexed implementation, uint48 startTime, uint48 endTime);

    /// @notice Emitted when the upgrade delay period for a new implementation proposed by the voter body is reset.
    /// @param implementation The implementation the delay is reset for.
    event VoterBodyUpgradeDelayReset(address indexed implementation);

    /// @notice Emitted when the upgrade delay period for a new implementation proposed by the council is started.
    /// @param implementation The implementation the delay is started for.
    /// @param startTime The start time.
    /// @param endTime The end time.
    event CouncilUpgradeDelayStarted(address indexed implementation, uint48 startTime, uint48 endTime);

    /// @notice Emitted when the upgrade delay period for a new implementation proposed by the council is reset.
    /// @param implementation The implementation the delay is reset for.
    event CouncilUpgradeDelayReset(address indexed implementation);

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

    /// @notice Revokes the vote from a proposed implementation.
    /// @param proposedImpl The proposed implementation to revoke the vote for.
    function revokeVote(address proposedImpl) external;

    /// @notice Starts the delay period for the winning implementation.
    /// @param winningImpl The winning implementation to activate the delay period for.
    function startVoterBodyUpgradeDelay(address winningImpl) external;

    /// @notice Resets the delay period for a losing implementation.
    /// @param losingImpl The losing implementation to reset the delay period for.
    function resetVoterBodyUpgradeDelay(address losingImpl) external;

    /// @notice Proposes an implementation to upgrade. This is only callable by the council.
    /// @param proposedImpl The implementation proposed by the council.
    function proposeCouncilUpgrade(address proposedImpl) external;

    // TODO Improve natespec.
    /// @notice Cancel the upgrade to the implementation proposed by the governance council. This is only callable by the council.
    function cancelCouncilUpgrade() external;

    // TODO Improve natespec.
    /// @notice Marks the council upgrade as failed if there is any other implementation that has reached quorum.
    function vetoCouncilUpgrade() external;

    /// @notice Calculates the quorum based on the current locked supply.
    /// @return threshold The calculated quorum threshold.
    function calculateQuorumThreshold() external view returns (uint256 threshold);

    /// @notice Returns the votum of the caller for a proposed implementation.
    /// @param proposedImpl The proposed implementation to return the votum for.
    /// @return votes The votum of the caller.
    function votum(address proposedImpl) external view returns (uint256 votes);

    /// @notice Returns the total votes for a proposed implementation.
    /// @param proposedImpl The proposed implementation to return the total votes for.
    /// @return votes The total votes of the proposed implementation.
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
    /// @param locked The locked supply.
    function lockedSupply() external view returns (uint256 locked);

    // TODO improve naming
    /// @notice Returns the implementation for which the delay was started.
    /// @return delayedImpl The implementation the delay was started for.
    function voterBodyDelayedUpgradeImplementation() external view returns (address delayedImpl);

    /// @notice Returns the delay end time of the implementation proposed by the voter body.
    /// @return endTime The delay end time.
    function voterBodyDelayEndTime() external view returns (uint48 endTime);

    /// @notice Returns the current implementation
    /// @return current The current implementation.
    function implementation() external view returns (address current);

    /// @notice Returns the proposed implementation with the respective rank.
    /// @return rankedImplementation The proposed implementation with the respective rank.
    function proposedImplementationByRank(uint48 rank) external view returns (address rankedImplementation);

    /// @notice Returns the address of the governance council.
    /// @return council The governance council address.
    function governanceCouncil() external view returns (address council);
}
