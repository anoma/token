// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Parameters} from "../src/libs/Parameters.sol";
import {XanGovernorFixture} from "./XanGovernorFixture.sol";

/// @notice Demonstrates DAO voting with the `ERC20Votes`-compatible XAN token: voting power is delegated from the
/// token, proposals run through their lifecycle, quorum is enforced, and a passing proposal executes a treasury
/// transfer of XAN held by the timelock.
contract XanGovernorVotingTest is XanGovernorFixture {
    /// @notice The amount of XAN funded into the DAO treasury (the timelock) for the spending demo.
    uint256 internal constant _TREASURY = 1_000_000e18;

    function test_for_vote_is_tallied_with_the_voters_weight() public {
        (uint256 proposalId, address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            _treasuryTransferProposal("tally");

        // Funding the treasury moved some weight out of `_voter`; the vote should count the remaining delegation.
        uint256 weight = _xanToken.getVotes(_voter);

        vm.prank(_voter);
        _governor.propose(targets, values, calldatas, "tally");

        _warpIntoVotingPeriod();
        assertEq(uint8(_governor.state(proposalId)), uint8(IGovernor.ProposalState.Active));

        vm.prank(_voter);
        _governor.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));

        (uint256 against, uint256 forVotes, uint256 abstain) = _governor.proposalVotes(proposalId);
        assertEq(forVotes, weight);
        assertEq(weight, Parameters.SUPPLY - _TREASURY);
        assertEq(against, 0);
        assertEq(abstain, 0);

        _warpPastVotingPeriod();
        assertEq(uint8(_governor.state(proposalId)), uint8(IGovernor.ProposalState.Succeeded));
    }

    function test_proposal_is_defeated_without_quorum() public {
        // `_OTHER` self-delegates but holds no tokens, so its `For` vote cannot reach quorum.
        vm.prank(_OTHER);
        _xanToken.delegate(_OTHER);
        vm.warp(block.timestamp + 1);

        (uint256 proposalId, address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            _treasuryTransferProposal("no quorum");

        vm.prank(_OTHER);
        _governor.propose(targets, values, calldatas, "no quorum");

        _warpIntoVotingPeriod();
        vm.prank(_OTHER);
        _governor.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For)); // Vote `For` but with zero weight

        _warpPastVotingPeriod();
        assertEq(uint8(_governor.state(proposalId)), uint8(IGovernor.ProposalState.Defeated));
    }

    function test_passing_proposal_executes_a_treasury_transfer() public {
        (, address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            _treasuryTransferProposal("spend treasury");

        assertEq(_xanToken.balanceOf(address(_timelock)), _TREASURY);
        assertEq(_xanToken.balanceOf(_OTHER), 0);

        uint256 proposalId = _passProposal(targets, values, calldatas, "spend treasury");

        assertEq(uint8(_governor.state(proposalId)), uint8(IGovernor.ProposalState.Executed));
        assertEq(_xanToken.balanceOf(address(_timelock)), 0);
        assertEq(_xanToken.balanceOf(_OTHER), _TREASURY);
    }

    function test_voting_power_is_delegated_from_the_xanToken() public view {
        // The governor reads voting power straight from the token's delegation checkpoints.
        assertEq(_governor.getVotes(_voter, block.timestamp - 1), _xanToken.getVotes(_voter));
        assertEq(_xanToken.getVotes(_voter), Parameters.SUPPLY);
    }

    /// @notice Funds the DAO treasury with unlocked XAN and builds a proposal to transfer it all to `_OTHER`.
    /// @dev Vesting is fast-forwarded so the supply is fully unlocked and spendable before funding the timelock.
    function _treasuryTransferProposal(string memory description)
        internal
        returns (uint256 proposalId, address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    {
        vm.warp(_xanToken.vestingEnd());
        vm.startPrank(_voter);
        _xanToken.unlock();
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        _xanToken.transfer(address(_timelock), _TREASURY);
        vm.stopPrank();
        vm.warp(block.timestamp + 1);

        targets = new address[](1);
        targets[0] = address(_xanToken);
        values = new uint256[](1);
        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(IERC20.transfer, (_OTHER, _TREASURY));

        proposalId = _governor.hashProposal(targets, values, calldatas, keccak256(bytes(description)));
    }
}
