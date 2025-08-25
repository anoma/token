// SPDX-License-Identifier: AGPL-3.0-or-later

/*
 * Certora Verification Language (CVL) Specification for XanV1 Contract
 * 
 * This specification formally verifies the XanV1 contract bytecode using Certora Prover.
 * It includes invariants, rules, and properties that ensure the contract behaves correctly.
 */

using XanV1 as xanV1;

// ========================================
// Methods and Function Declarations
// ========================================

methods {
    // ERC20 methods
    function totalSupply() external returns (uint256) envfree;
    function balanceOf(address) external returns (uint256) envfree;
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function approve(address, uint256) external returns (bool);
    function allowance(address, address) external returns (uint256) envfree;

    // XanV1 specific methods
    function lock(uint256) external;
    function transferAndLock(address, uint256) external;
    function castVote(address) external;
    function scheduleVoterBodyUpgrade() external;
    function cancelVoterBodyUpgrade() external;
    function scheduleCouncilUpgrade(address) external;
    function cancelCouncilUpgrade() external;
    function vetoCouncilUpgrade() external;
    
    // View functions
    function lockedBalanceOf(address) external returns (uint256) envfree;
    function unlockedBalanceOf(address) external returns (uint256) envfree;
    function lockedSupply() external returns (uint256) envfree;
    function getVotes(address, address) external returns (uint256) envfree;
    function totalVotes(address) external returns (uint256) envfree;
    function mostVotedImplementation() external returns (address) envfree;
    function calculateQuorumThreshold() external returns (uint256) envfree;
    function scheduledVoterBodyUpgrade() external returns (address, uint48) envfree;
    function scheduledCouncilUpgrade() external returns (address, uint48) envfree;
    function governanceCouncil() external returns (address) envfree;
    function implementation() external returns (address) envfree;
}

function scheduledVoterBodyUpgradeImplAddress() returns(address) {
    address implAddress;
    uint48 endTime;
    implAddress, endTime = scheduledVoterBodyUpgrade();
    return implAddress; 
}

function scheduledCouncilUpgradeImplAddress() returns(address) {
    address implAddress;
    uint48 endTime;
    implAddress, endTime = scheduledCouncilUpgrade();
    return implAddress;
}

// ========================================
// Ghost Variables and Hooks
// ========================================

// Ghost variable to track total supply conservation
ghost uint256 ghostTotalSupply {
    init_state axiom ghostTotalSupply == 10000000000000000000000000000; // 10^28
}

// ========================================
// Invariants
// ========================================

// Invariant 1: Total supply is always conserved
invariant totalSupplyConservation()
    totalSupply() == ghostTotalSupply
    {
        preserved with (env e) {
            require e.msg.sender != 0;
        }
    }

// Invariant 2: Locked balance never exceeds total balance
invariant lockedBalanceConstraint(address user)
    lockedBalanceOf(user) <= balanceOf(user)
    {
        preserved with (env e) {
            require e.msg.sender != 0;
            require user != 0;
        }
    }

// Invariant 3: Unlocked balance is correctly calculated
invariant unlockedBalanceCorrectness(address user)
    unlockedBalanceOf(user) == balanceOf(user) - lockedBalanceOf(user)
    {
        preserved with (env e) {
            require e.msg.sender != 0;
            require user != 0;
        }
    }

// Invariant 4: Quorum threshold is reasonable
invariant quorumThresholdReasonable()
    calculateQuorumThreshold() <= lockedSupply() &&
    calculateQuorumThreshold() == (lockedSupply() * 1) / 2
    {
        preserved with (env e) {
            require e.msg.sender != 0;
        }
    }

// Invariant 5: Only one upgrade can be scheduled at a time
invariant upgradeSchedulingMutualExclusion()
    !(scheduledVoterBodyUpgradeImplAddress() != 0 && scheduledCouncilUpgradeImplAddress() != 0)
    {
        preserved with (env e) {
            require e.msg.sender != 0;
        }
    }

// ========================================
// Rules (Properties)
// ========================================

// Lock function increases locked balance and locked supply
rule lockIncreasesLockedBalanceAndSupply(env e, uint256 value) {
    require e.msg.sender != 0;
    require value > 0;
    
    uint256 oldLockedBalance = lockedBalanceOf(e.msg.sender);
    uint256 oldLockedSupply = lockedSupply();
    uint256 oldUnlockedBalance = unlockedBalanceOf(e.msg.sender);
    
    require oldUnlockedBalance >= value; // Precondition: sufficient unlocked balance
    
    lock(e, value);
    
    uint256 newLockedBalance = lockedBalanceOf(e.msg.sender);
    uint256 newLockedSupply = lockedSupply();
    
    assert newLockedBalance == oldLockedBalance + value;
    assert newLockedSupply == oldLockedSupply + value;
    assert balanceOf(e.msg.sender) == oldLockedBalance + oldUnlockedBalance; // Total balance unchanged
}

// Lock function reverts if insufficient unlocked balance
rule lockRevertsOnInsufficientBalance(env e, uint256 value) {
    require e.msg.sender != 0;
    require value > 0;
    
    uint256 unlockedBalance = unlockedBalanceOf(e.msg.sender);
    
    require unlockedBalance < value; // Insufficient unlocked balance
    
    lock@withrevert(e, value);
    
    assert lastReverted;
}

// Locked tokens cannot be transferred while locked
rule lockedTokensCannotBeTransferred(env e, address to, uint256 amount) {
    require e.msg.sender != 0;
    require to != 0;
    require amount > 0;
    
    uint256 unlockedBalance = unlockedBalanceOf(e.msg.sender);
    require amount > unlockedBalance; // Trying to transfer more than unlocked
    
    transfer@withrevert(e, to, amount);
    assert lastReverted;
}

// Locked tokens cannot be transferred via transferFrom
rule lockedTokensCannotBeTransferredFrom(env e, address from, address to, uint256 amount) {
    require e.msg.sender != 0;
    require from != 0;
    require to != 0;
    require amount > 0;
    
    uint256 unlockedBalance = unlockedBalanceOf(from);
    require amount > unlockedBalance; // Trying to transfer more than unlocked
    
    transferFrom@withrevert(e, from, to, amount);
    assert lastReverted;
}

// Vote casting increases votes monotonically
rule castVoteMonotonicity(env e, address proposedImpl) {
    require e.msg.sender != 0;
    require proposedImpl != 0;
    
    uint256 oldVotes = getVotes(e.msg.sender, proposedImpl);
    uint256 lockedBalance = lockedBalanceOf(e.msg.sender);
    
    require lockedBalance > oldVotes; // Precondition: can increase votes
    
    castVote(e, proposedImpl);
    
    uint256 newVotes = getVotes(e.msg.sender, proposedImpl);
    
    assert newVotes == lockedBalance;
    assert newVotes >= oldVotes; // Monotonicity
}

// Vote casting reverts if insufficient locked balance
rule castVoteRevertsOnInsufficientLockedBalance(env e, address proposedImpl) {
    require e.msg.sender != 0;
    require proposedImpl != 0;
    
    uint256 oldVotes = getVotes(e.msg.sender, proposedImpl);
    uint256 lockedBalance = lockedBalanceOf(e.msg.sender);
    
    require lockedBalance <= oldVotes; // Insufficient locked balance to increase votes
    
    castVote@withrevert(e, proposedImpl);
    
    assert lastReverted;
}

// Transfer and lock atomically transfers and locks tokens
rule transferAndLockAtomicity(env e, address to, uint256 value) {
    require e.msg.sender != 0;
    require to != 0;
    require to != e.msg.sender;
    require value > 0;
    
    uint256 senderOldBalance = balanceOf(e.msg.sender);
    uint256 senderOldUnlockedBalance = unlockedBalanceOf(e.msg.sender);
    uint256 recipientOldBalance = balanceOf(to);
    uint256 recipientOldLockedBalance = lockedBalanceOf(to);
    uint256 oldLockedSupply = lockedSupply();
    
    require senderOldUnlockedBalance >= value; // Sufficient unlocked balance
    
    transferAndLock(e, to, value);
    
    uint256 senderNewBalance = balanceOf(e.msg.sender);
    uint256 recipientNewBalance = balanceOf(to);
    uint256 recipientNewLockedBalance = lockedBalanceOf(to);
    uint256 newLockedSupply = lockedSupply();
    
    assert senderNewBalance == senderOldBalance - value;
    assert recipientNewBalance == recipientOldBalance + value;
    assert recipientNewLockedBalance == recipientOldLockedBalance + value;
    assert newLockedSupply == oldLockedSupply + value;
}

// Unlocked tokens can be transferred
rule unlockedTokensTransferable(env e, address to, uint256 amount) {
    require e.msg.sender != 0;
    require to != 0;
    require to != e.msg.sender;
    require amount > 0;
    
    uint256 unlockedBalance = unlockedBalanceOf(e.msg.sender);
    require amount <= unlockedBalance; // Sufficient unlocked balance
    
    uint256 senderBalanceBefore = balanceOf(e.msg.sender);
    uint256 recipientBalanceBefore = balanceOf(to);
    
    // Transfer should not revert when conditions are met
    transfer(e, to, amount);
    
    uint256 senderBalanceAfter = balanceOf(e.msg.sender);
    uint256 recipientBalanceAfter = balanceOf(to);
    
    assert senderBalanceAfter == senderBalanceBefore - amount;
    assert recipientBalanceAfter == recipientBalanceBefore + amount;
}

// Schedule voter body upgrade requires quorum
rule scheduleVoterBodyUpgradeRequiresQuorum(env e) {
    require e.msg.sender != 0;
    
    address mostVoted = mostVotedImplementation();
    uint256 totalVotesForMostVoted = totalVotes(mostVoted);
    uint256 quorumThreshold = calculateQuorumThreshold();
    uint256 currentLockedSupply = lockedSupply();
    mathint minLockedSupply = totalSupply() / 4; // 25% of total supply
    
    // Preconditions for successful scheduling
    require mostVoted != 0;
    require totalVotesForMostVoted >= quorumThreshold + 1; // Quorum reached
    require currentLockedSupply >= minLockedSupply; // Min locked supply (25%)
    require scheduledVoterBodyUpgradeImplAddress() == 0; // No upgrade already scheduled

    scheduleVoterBodyUpgrade(e);
    
    address scheduledImpl;
    uint48 scheduledEndTime;
    scheduledImpl, scheduledEndTime = scheduledVoterBodyUpgrade();
    
    assert scheduledImpl == mostVoted;
    assert scheduledEndTime > e.block.timestamp;
    assert scheduledCouncilUpgradeImplAddress() == 0; // Council upgrade should be cancelled
}

// Schedule voter body upgrade reverts without quorum
rule scheduleVoterBodyUpgradeRevertsWithoutQuorum(env e) {
    require e.msg.sender != 0;
    
    address mostVoted = mostVotedImplementation();
    uint256 totalVotesForMostVoted = totalVotes(mostVoted);
    uint256 quorumThreshold = calculateQuorumThreshold();
    uint256 currentLockedSupply = lockedSupply();
    mathint minLockedSupply = totalSupply() / 4; // 25% of total supply

    // Conditions that should cause revert
    require mostVoted == 0 || 
            totalVotesForMostVoted < quorumThreshold + 1 || 
            currentLockedSupply < minLockedSupply;
    
    scheduleVoterBodyUpgrade@withrevert(e);
    
    assert lastReverted;
}

// Council can only schedule upgrade when voter body doesn't have quorum
rule councilUpgradeOnlyWhenNoVoterBodyQuorum(env e, address impl) {
    require e.msg.sender != 0;
    require impl != 0;
    require e.msg.sender == governanceCouncil(); // Only council can call
    
    address mostVoted = mostVotedImplementation();
    uint256 totalVotesForMostVoted = totalVotes(mostVoted);
    uint256 quorumThreshold = calculateQuorumThreshold();
    uint256 currentLockedSupply = lockedSupply();
    mathint minLockedSupply = totalSupply() / 4; // 25% of total supply
    
    // Precondition: voter body doesn't have quorum
    require !(totalVotesForMostVoted >= quorumThreshold + 1 && 
              currentLockedSupply >= minLockedSupply);
    require scheduledCouncilUpgradeImplAddress() == 0; // No council upgrade scheduled

    scheduleCouncilUpgrade(e, impl);
    
    address scheduledImpl;
    uint48 scheduledEndTime;
    scheduledImpl, scheduledEndTime = scheduledCouncilUpgrade();
    
    assert scheduledImpl == impl;
    assert scheduledEndTime > e.block.timestamp;
}

// Council upgrade reverts when voter body has quorum
rule councilUpgradeRevertsWhenVoterBodyHasQuorum(env e, address impl) {
    require e.msg.sender != 0;
    require impl != 0;
    require e.msg.sender == governanceCouncil();
    
    address mostVoted = mostVotedImplementation();
    uint256 totalVotesForMostVoted = totalVotes(mostVoted);
    uint256 quorumThreshold = calculateQuorumThreshold();
    uint256 currentLockedSupply = lockedSupply();
    mathint minLockedSupply = totalSupply() / 4; // 25% of total supply
    
    // Condition: voter body has quorum
    require totalVotesForMostVoted >= quorumThreshold + 1 && 
            currentLockedSupply >= minLockedSupply;

    scheduleCouncilUpgrade@withrevert(e, impl);
    
    assert lastReverted;
}

// Voter body upgrade cancellation authority and conditions
rule cancelVoterBodyUpgradeConditions(env e) {
    require e.msg.sender != 0;
    
    address scheduledImpl;
    uint48 scheduledEndTime;
    scheduledImpl, scheduledEndTime = scheduledVoterBodyUpgrade();
    
    require scheduledImpl != 0; // Must have scheduled upgrade
    
    address mostVoted = mostVotedImplementation();
    uint256 totalVotesForMostVoted = totalVotes(mostVoted);
    uint256 quorumThreshold = calculateQuorumThreshold();
    uint256 currentLockedSupply = lockedSupply();
    mathint minLockedSupply = totalSupply() / 4; // 25% of total supply

    // Cancellation should succeed when:
    // (a) delay period has elapsed OR
    // (b) scheduled upgrade no longer meets quorum requirements OR is no longer most voted
    require e.block.timestamp >= scheduledEndTime || 
            totalVotesForMostVoted < quorumThreshold + 1 ||
            currentLockedSupply < minLockedSupply ||
            mostVoted != scheduledImpl;
    
    cancelVoterBodyUpgrade(e);
    
    assert scheduledVoterBodyUpgradeImplAddress() == 0; // Upgrade cancelled
}

// Cancellation preserves token and vote state
rule cancellationPreservesTokenState(env e, address user, address impl) {
    require e.msg.sender != 0;
    require user != 0;
    require impl != 0;
    
    // Record state before cancellation
    uint256 lockedBalanceBefore = lockedBalanceOf(user);
    uint256 totalBalanceBefore = balanceOf(user);
    uint256 votesBefore = getVotes(user, impl);
    uint256 lockedSupplyBefore = lockedSupply();
    
    address scheduledImpl = scheduledVoterBodyUpgradeImplAddress();
    require scheduledImpl != 0; // Must have upgrade to cancel
    
    cancelVoterBodyUpgrade(e);
    
    // Verify state preservation
    uint256 lockedBalanceAfter = lockedBalanceOf(user);
    uint256 totalBalanceAfter = balanceOf(user);
    uint256 votesAfter = getVotes(user, impl);
    uint256 lockedSupplyAfter = lockedSupply();
    
    assert lockedBalanceAfter == lockedBalanceBefore; // Locked balances unchanged
    assert totalBalanceAfter == totalBalanceBefore; // Total balances unchanged
    assert votesAfter == votesBefore; // Vote counts unchanged
    assert lockedSupplyAfter == lockedSupplyBefore; // Locked supply unchanged
}

// Veto council upgrade requires voter body quorum
rule vetoCouncilUpgradeRequiresVoterBodyQuorum(env e) {
    require e.msg.sender != 0;

    address councilScheduledImpl = scheduledCouncilUpgradeImplAddress();
    require councilScheduledImpl != 0; // Council upgrade must be scheduled
    
    address mostVoted = mostVotedImplementation();
    uint256 totalVotesForMostVoted = totalVotes(mostVoted);
    uint256 quorumThreshold = calculateQuorumThreshold();
    uint256 currentLockedSupply = lockedSupply();
    mathint minLockedSupply = totalSupply() / 4; // 25% of total supply

    // Precondition: voter body has quorum
    require totalVotesForMostVoted >= quorumThreshold + 1 && 
            currentLockedSupply >= minLockedSupply;

    vetoCouncilUpgrade(e);

    assert scheduledCouncilUpgradeImplAddress() == 0; // Council upgrade cancelled
}

// Veto council upgrade reverts without voter body quorum
rule vetoCouncilUpgradeRevertsWithoutVoterBodyQuorum(env e) {
    require e.msg.sender != 0;

    address councilScheduledImpl = scheduledCouncilUpgradeImplAddress();
    require councilScheduledImpl != 0; // Council upgrade must be scheduled
    
    address mostVoted = mostVotedImplementation();
    uint256 totalVotesForMostVoted = totalVotes(mostVoted);
    uint256 quorumThreshold = calculateQuorumThreshold();
    uint256 currentLockedSupply = lockedSupply();
    mathint minLockedSupply = totalSupply() / 4; // 25% of total supply

    // Condition: voter body doesn't have quorum
    require !(totalVotesForMostVoted >= quorumThreshold + 1 && 
              currentLockedSupply >= minLockedSupply);

    vetoCouncilUpgrade@withrevert(e);
    
    assert lastReverted;
}

// Only council can perform council operations
rule onlyCouncilCanPerformCouncilOperations(env e, address impl) {
    require e.msg.sender != 0;
    require impl != 0;
    require e.msg.sender != governanceCouncil(); // Not the council
    
    scheduleCouncilUpgrade@withrevert(e, impl);
    assert lastReverted;
    
    cancelCouncilUpgrade@withrevert(e);
    assert lastReverted;
}

// Most voted implementation has the highest vote count
rule mostVotedImplementationHasMaxVotes(env e, address impl) {
    require impl != 0;
    
    address mostVoted = mostVotedImplementation();
    uint256 mostVotedVotes = totalVotes(mostVoted);
    uint256 implVotes = totalVotes(impl);
    
    assert implVotes <= mostVotedVotes;
}

// Scheduling voter body upgrade cancels conflicting council upgrade
rule upgradeSchedulingCancelsConflicts(env e) {
    require e.msg.sender != 0;
    
    // If council upgrade is scheduled
    address councilScheduledBefore = scheduledCouncilUpgradeImplAddress();
    require councilScheduledBefore != 0;
    
    // And voter body schedules an upgrade
    address mostVoted = mostVotedImplementation();
    uint256 totalVotesForMostVoted = totalVotes(mostVoted);
    uint256 quorumThreshold = calculateQuorumThreshold();
    uint256 currentLockedSupply = lockedSupply();
    mathint minLockedSupply = totalSupply() / 4; // 25% of total supply

    require mostVoted != 0;
    require totalVotesForMostVoted >= quorumThreshold + 1;
    require currentLockedSupply >= minLockedSupply;
    require scheduledVoterBodyUpgradeImplAddress() == 0;

    scheduleVoterBodyUpgrade(e);
    
    // Council upgrade should be cancelled
    assert scheduledCouncilUpgradeImplAddress() == 0;
}

// ========================================
// Parametric Rules
// ========================================

// Locked balances can only increase (tokens can't be unlocked)
rule lockedBalancesOnlyIncrease(env e, method f, calldataarg args, address user)
    filtered { f -> !f.isView }
{
    require user != 0;
    
    uint256 lockedBalanceBefore = lockedBalanceOf(user);
    
    f(e, args);
    
    uint256 lockedBalanceAfter = lockedBalanceOf(user);
    
    assert lockedBalanceAfter >= lockedBalanceBefore;
}

// Vote counts can only increase (monotonicity)
rule voteMonotonicity(env e, method f, calldataarg args, address voter, address impl)
    filtered { f -> !f.isView }
{
    require voter != 0;
    require impl != 0;
    
    uint256 votesBefore = getVotes(voter, impl);
    
    f(e, args);
    
    uint256 votesAfter = getVotes(voter, impl);
    
    assert votesAfter >= votesBefore;
}
