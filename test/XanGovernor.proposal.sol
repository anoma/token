// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Parameters} from "../src/libs/Parameters.sol";
import {XanGovernorFixture} from "./XanGovernorFixture.sol";

/// @notice Covers the governor's configuration getters and the proposal cancellation path: proposal creation is gated
/// by the threshold, quorum tracks the configured supply fraction, timelock proposals report as needing queuing, and a
/// proposer can withdraw a still-pending proposal.
contract XanGovernorProposalTest is XanGovernorFixture {
    function test_proposalThreshold_gates_proposal_creation() public {
        assertEq(_governor.proposalThreshold(), _PROPOSAL_THRESHOLD);

        // `_OTHER` holds no voting power, so it is below the threshold and cannot open a proposal.
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _noopProposal();
        vm.prank(_OTHER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor.GovernorInsufficientProposerVotes.selector, _OTHER, 0, _PROPOSAL_THRESHOLD
            ),
            address(_governor)
        );
        _governor.propose(targets, values, calldatas, "below threshold");
    }

    function test_proposalNeedsQueuing_returns_true_for_proposals() public {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _noopProposal();
        vm.prank(_voterA);
        uint256 proposalId = _governor.propose(targets, values, calldatas, "needs queuing");

        // This timelock governor requires every proposal to queue before it can be executed.
        assertTrue(_governor.proposalNeedsQueuing(proposalId));
    }

    function test_cancel_cancels_pending_proposals_if_called_by_the_proposer() public {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _noopProposal();
        vm.prank(_voterA);
        uint256 proposalId = _governor.propose(targets, values, calldatas, "cancel me");
        assertEq(uint8(_governor.state(proposalId)), uint8(IGovernor.ProposalState.Pending));

        // Cancellation is only allowed by the proposer while the proposal is still pending (before voting opens).
        vm.prank(_voterA);
        _governor.cancel(targets, values, calldatas, keccak256(bytes("cancel me")));
        assertEq(uint8(_governor.state(proposalId)), uint8(IGovernor.ProposalState.Canceled));
    }

    function test_cancel_reverts_for_pending_proposals_if_the_caller_is_not_the_proposer() public {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _noopProposal();
        vm.prank(_voterA);
        uint256 proposalId = _governor.propose(targets, values, calldatas, "cancel me");
        assertEq(uint8(_governor.state(proposalId)), uint8(IGovernor.ProposalState.Pending));

        // Cancellation is only allowed by the proposer while the proposal is still pending (before voting opens).
        vm.prank(_OTHER);
        vm.expectRevert(
            abi.encodeWithSelector(IGovernor.GovernorUnableToCancel.selector, proposalId, _OTHER), address(_governor)
        );
        _governor.cancel(targets, values, calldatas, keccak256(bytes("cancel me")));
    }

    function test_quorum_is_half_of_the_voting_supply() public view {
        // The fixture reuses the V1 ratio (50%); the whole supply is the voting supply, so quorum is half of it.
        assertEq(_QUORUM_NUMERATOR, 50);
        assertEq(_governor.quorum(block.timestamp - 1), Parameters.SUPPLY / 2);
    }

    /// @notice A minimal, harmless single-call proposal used only to drive lifecycle transitions.
    function _noopProposal()
        internal
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    {
        targets = new address[](1);
        targets[0] = address(_xanToken);
        values = new uint256[](1);
        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(IERC20.transfer, (_OTHER, 0));
    }
}
