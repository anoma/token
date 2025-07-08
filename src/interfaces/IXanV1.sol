// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

/// @title IXanV1
/// @author Anoma Foundation, 2025
/// @notice The interface of the Anoma (XAN) token contract version 1.
/// @custom:security-contact security@anoma.foundation
interface IXanV1 {
    /// @notice Emitted when tokens are locked.
    /// @param account The owning account.
    /// @param value The number of tokens being locked.
    event Locked(address indexed account, uint256 value);

    /// @notice Emitted when a vote is cast for a implementation.
    /// @param voter The voter address.
    /// @param impl The implementation the vote was cast for.
    /// @param value The number of votes cast.
    event VoteCast(address indexed voter, address indexed impl, uint256 value);

    /// @notice Emitted when the most voted implementation gets updated.
    /// @param newMostVotedImpl The new most-voted implementation.
    event MostVotedImplementationUpdated(address indexed newMostVotedImpl);

    /// @notice Emitted when the upgrade to a new implementation proposed by the voter body is scheduled.
    /// @param impl The implementation that has been scheduled.
    /// @param endTime The end time of the delay period.
    event VoterBodyUpgradeScheduled(address indexed impl, uint48 endTime);

    /// @notice Emitted  when the upgrade to a new implementation proposed by the voter body is cancelled.
    /// @param impl The implementation that has been cancelled.
    event VoterBodyUpgradeCancelled(address indexed impl);

    /// @notice Emitted when the upgrade to a new implementation proposed by the governance council is scheduled.
    /// @param impl The implementation that has been scheduled.
    /// @param endTime The end time of the delay period.
    event CouncilUpgradeScheduled(address indexed impl, uint48 endTime);

    /// @notice Emitted when the upgrade scheduled by the governance council is cancelled.
    /// @param impl The implementation to which the upgrade has been cancelled by the governance council.
    event CouncilUpgradeCancelled(address indexed impl);

    /// @notice Emitted when the upgrade to a new implementation proposed by the governance council is vetoed
    /// by the voter body.
    /// @param impl The implementation to which the upgrade has been vetoed by the voter body.
    event CouncilUpgradeVetoed(address indexed impl);

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

    /// @notice Schedules the upgrade to the best-ranked implementation proposed by the voter body.
    function scheduleVoterBodyUpgrade() external;

    /// @notice Cancels the upgrade if the scheduled implementation is not the best-ranked anymore and the delay period
    /// has passed.
    function cancelVoterBodyUpgrade() external;

    /// @notice Schedules the upgrade to a new implementation. This is only callable by the council.
    /// @param impl The implementation proposed by the council.
    function scheduleCouncilUpgrade(address impl) external;

    /// @notice Cancels the upgrade proposed by the governance council.
    /// This is only callable by the council.
    function cancelCouncilUpgrade() external;

    /// @notice Vetos the council upgrade, which cancels it.
    /// This can be called by anyone, if there is an implementation proposed by the voter body that has reached quorum.
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
    /// @return unlockedBalance The unlocked balance.
    function unlockedBalanceOf(address from) external view returns (uint256 unlockedBalance);

    /// @notice Returns the locked token balance of an account.
    /// @param from The account to query.
    /// @return lockedBalance The locked balance.
    function lockedBalanceOf(address from) external view returns (uint256 lockedBalance);

    /// @notice Returns the locked total supply of the token.
    /// @return locked The locked supply.
    function lockedSupply() external view returns (uint256 locked);

    /// @notice Returns the upgrade scheduled by the voter body or `ScheduledUpgrade(0)`
    /// if no implementation has reached quorum yet.
    /// @return impl The implementation to upgrade to.
    /// @return endTime The end time of the scheduled delay.
    function scheduledVoterBodyUpgrade() external view returns (address impl, uint48 endTime);

    /// @notice Returns the upgrade scheduled by the council or `ScheduledUpgrade(0)`
    /// if no implementation has reached quorum yet.
    /// @return impl The implementation to upgrade to.
    /// @return endTime The end time of the scheduled delay.
    function scheduledCouncilUpgrade() external view returns (address impl, uint48 endTime);

    /// @notice Returns the current implementation
    /// @return current The current implementation.
    function implementation() external view returns (address current);

    /// @notice Returns the most voted implementation.
    /// @return mostVotedImpl The most voted implementation.
    function mostVotedImplementation() external view returns (address mostVotedImpl);

    /// @notice Returns the address of the governance council.
    /// @return council The governance council address.
    function governanceCouncil() external view returns (address council);
}
