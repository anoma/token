// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {XanV2} from "../src/XanV2.sol";
import {XanGovernorFixture} from "./XanGovernorFixture.sol";

/// @notice Demonstrates DAO voting with the `ERC20Votes`-compatible XAN token.
contract XanGovernorVotingTest is XanGovernorFixture {
    using SafeERC20 for XanV2;

    function test_votes_are_tallied_by_delegated_weight() public {
        uint256 proposalId = _proposeAndOpenVoting("tally");

        _castVote(proposalId, _voterA, GovernorCountingSimple.VoteType.For);
        _castVote(proposalId, _voterB, GovernorCountingSimple.VoteType.Against);
        _castVote(proposalId, _voterC, GovernorCountingSimple.VoteType.Abstain);

        (uint256 against, uint256 forVotes, uint256 abstain) = _governor.proposalVotes(proposalId);
        assertEq(forVotes, _HALF);
        assertEq(against, _QUARTER);
        assertEq(abstain, _QUARTER);
    }

    function test_proposal_succeeds_when_quorum_is_exactly_met() public {
        // A's 50% `For` vote equals the quorum exactly (not a wei more) and faces no opposition, so the proposal passes.
        uint256 proposalId = _proposeAndOpenVoting("exact quorum");

        _castVote(proposalId, _voterA, GovernorCountingSimple.VoteType.For);

        _warpPastVotingPeriod();
        assertEq(uint8(_governor.state(proposalId)), uint8(IGovernor.ProposalState.Succeeded));
    }

    function test_proposal_is_defeated_when_quorum_is_not_reached() public {
        // B's 25% `For` is the only vote cast, short of the 50% quorum.
        uint256 proposalId = _proposeAndOpenVoting("below quorum");

        _castVote(proposalId, _voterB, GovernorCountingSimple.VoteType.For);

        _warpPastVotingPeriod();
        assertEq(uint8(_governor.state(proposalId)), uint8(IGovernor.ProposalState.Defeated));
    }

    function test_proposal_is_defeated_without_quorum() public {
        // No one votes, so the tally never reaches quorum.
        uint256 proposalId = _proposeAndOpenVoting("no votes");

        _warpPastVotingPeriod();
        assertEq(uint8(_governor.state(proposalId)), uint8(IGovernor.ProposalState.Defeated));
    }

    function test_abstain_counts_toward_quorum() public {
        // B's 25% `For` alone falls short of quorum, but A's 50% `Abstain` lifts participation over the 50% line while
        // leaving B's `For` as the only directional vote, so the proposal succeeds.
        uint256 proposalId = _proposeAndOpenVoting("abstain reaches quorum");

        _castVote(proposalId, _voterB, GovernorCountingSimple.VoteType.For);
        _castVote(proposalId, _voterA, GovernorCountingSimple.VoteType.Abstain);

        _warpPastVotingPeriod();
        assertEq(uint8(_governor.state(proposalId)), uint8(IGovernor.ProposalState.Succeeded));
    }

    function test_abstain_alone_does_not_pass_a_proposal() public {
        // A's 50% `Abstain` reaches quorum but casts no `For` support, so the proposal has no majority and is defeated.
        uint256 proposalId = _proposeAndOpenVoting("abstain only");

        _castVote(proposalId, _voterA, GovernorCountingSimple.VoteType.Abstain);

        _warpPastVotingPeriod();
        assertEq(uint8(_governor.state(proposalId)), uint8(IGovernor.ProposalState.Defeated));
    }

    function test_proposal_is_defeated_when_for_ties_against() public {
        // A votes `For` (50%) while B and C vote `Against` (25% each). Quorum is reached, but a tie is not a strict
        // majority: `For` must exceed `Against`.
        uint256 proposalId = _proposeAndOpenVoting("tie");

        _castVote(proposalId, _voterA, GovernorCountingSimple.VoteType.For);
        _castVote(proposalId, _voterB, GovernorCountingSimple.VoteType.Against);
        _castVote(proposalId, _voterC, GovernorCountingSimple.VoteType.Against);

        _warpPastVotingPeriod();
        assertEq(uint8(_governor.state(proposalId)), uint8(IGovernor.ProposalState.Defeated));
    }

    function test_proposal_succeeds_when_for_outweighs_against() public {
        // A and B vote `For` (75%) against C's `Against` (25%): quorum is reached and `For` beats `Against`.
        uint256 proposalId = _proposeAndOpenVoting("for majority");

        _castVote(proposalId, _voterA, GovernorCountingSimple.VoteType.For);
        _castVote(proposalId, _voterB, GovernorCountingSimple.VoteType.For);
        _castVote(proposalId, _voterC, GovernorCountingSimple.VoteType.Against);

        _warpPastVotingPeriod();
        assertEq(uint8(_governor.state(proposalId)), uint8(IGovernor.ProposalState.Succeeded));
    }

    function test_passing_proposal_executes_a_treasury_transfer() public {
        // Spending — unlike voting — needs *unlocked* tokens, so this flow legitimately fast-forwards past vesting and
        // unlocks before funding the DAO treasury (the timelock) with a quarter of the supply from A, dropping A to
        // 25%. A and B then both vote `For` (25% + 25% = the 50% quorum, exactly), and the passed proposal pays the
        // treasury out to `_OTHER`.
        vm.warp(_xanToken.vestingEnd());
        vm.startPrank(_voterA);
        _xanToken.unlock();
        _xanToken.safeTransfer(address(_timelock), _QUARTER);
        vm.stopPrank();
        vm.warp(_xanToken.vestingEnd() + 1); // checkpoint A's reduced weight before proposing

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _transferCalls(_OTHER, _QUARTER);
        string memory description = "spend treasury";

        vm.prank(_voterA);
        uint256 proposalId = _governor.propose(targets, values, calldatas, description);

        _warpIntoVotingPeriod();
        _castVote(proposalId, _voterA, GovernorCountingSimple.VoteType.For);
        _castVote(proposalId, _voterB, GovernorCountingSimple.VoteType.For);
        _warpPastVotingPeriod();

        bytes32 descriptionHash = keccak256(bytes(description));
        _governor.queue(targets, values, calldatas, descriptionHash);
        skip(_TIMELOCK_MIN_DELAY + 1);
        _governor.execute(targets, values, calldatas, descriptionHash);

        assertEq(uint8(_governor.state(proposalId)), uint8(IGovernor.ProposalState.Executed));
        assertEq(_xanToken.balanceOf(_OTHER), _QUARTER);
    }

    function test_voting_power_reflects_the_distribution() public view {
        assertEq(_xanToken.getVotes(_voterA), _HALF);
        assertEq(_xanToken.getVotes(_voterB), _QUARTER);
        assertEq(_xanToken.getVotes(_voterC), _QUARTER);
        // The governor reads voting power straight from the token's delegation checkpoints.
        assertEq(_governor.getVotes(_voterA, block.timestamp - 1), _HALF);
    }

    /// @notice Has A (which clears the proposal threshold) submit a harmless proposal, then opens the voting window.
    /// @dev The state-driven tests never execute the proposal, so its call (a zero-value transfer) is irrelevant.
    function _proposeAndOpenVoting(string memory description) internal returns (uint256 proposalId) {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _transferCalls(_OTHER, 0);
        vm.prank(_voterA);
        proposalId = _governor.propose(targets, values, calldatas, description);
        _warpIntoVotingPeriod();
    }

    /// @notice Casts `voter`'s vote on `proposalId` with the given support.
    function _castVote(uint256 proposalId, address voter, GovernorCountingSimple.VoteType support) internal {
        vm.prank(voter);
        _governor.castVote(proposalId, uint8(support));
    }

    /// @notice Builds a single ERC-20 transfer call executed by the timelock: `token.transfer(to, amount)`.
    function _transferCalls(address to, uint256 amount)
        internal
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    {
        targets = new address[](1);
        values = new uint256[](1);
        calldatas = new bytes[](1);
        targets[0] = address(_xanToken);
        calldatas[0] = abi.encodeCall(IERC20.transfer, (to, amount));
    }
}
