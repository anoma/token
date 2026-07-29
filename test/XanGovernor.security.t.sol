// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {
    GovernorVotesQuorumFraction
} from "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {XanGovernorFixture} from "./fixtures/XanGovernorFixture.sol";

/// @notice Pins the governance-only gates the layer's security rests on: `relay` (the voter body's instrument for
/// cancelling council upgrades), the governor's settings, and the timelock's delay are reachable only through a
/// passed proposal — never directly. Also pins the opt-in `#proposer=` front-running protection on `propose`
/// (see `docs/02-XanV2-governance.md` section 3).
contract XanGovernorSecurityTest is XanGovernorFixture {
    function test_relay_reverts_if_not_called_through_governance() public {
        // `relay` fronts the voter body's cancel of a council upgrade (`relay -> timelock.cancel`); outside a passed
        // proposal it must be unreachable, or anyone could cancel timelock operations in the governor's name.
        vm.prank(_voterA);
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorOnlyExecutor.selector, _voterA), address(_governor));
        _governor.relay(address(_timelock), 0, "");
    }

    function test_settings_setters_revert_if_not_called_through_governance() public {
        vm.startPrank(_voterA);

        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorOnlyExecutor.selector, _voterA), address(_governor));
        _governor.setVotingDelay(0);

        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorOnlyExecutor.selector, _voterA), address(_governor));
        _governor.setVotingPeriod(1);

        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorOnlyExecutor.selector, _voterA), address(_governor));
        _governor.setProposalThreshold(0);

        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorOnlyExecutor.selector, _voterA), address(_governor));
        _governor.updateQuorumNumerator(1);

        vm.stopPrank();
    }

    function test_timelock_updateDelay_reverts_if_not_called_by_the_timelock() public {
        vm.prank(_voterA);
        vm.expectRevert(
            abi.encodeWithSelector(TimelockController.TimelockUnauthorizedCaller.selector, _voterA), address(_timelock)
        );
        _timelock.updateDelay(0);
    }

    /// @dev The quorum moves only through a passed proposal, and a passed proposal can move it.
    function test_quorum_changes_only_through_a_passed_proposal() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(_governor);
        calldatas[0] = abi.encodeCall(GovernorVotesQuorumFraction.updateQuorumNumerator, (30));

        _passProposal({targets: targets, values: values, calldatas: calldatas, description: "lower the quorum to 30%"});

        assertEq(_governor.quorumNumerator(), 30);
    }

    /// @dev Pins the front-running risk documented in `docs/02-XanV2-governance.md` section 3: without a
    /// `#proposer=` suffix, `propose` is unrestricted, so another eligible account can submit the identical payload
    /// first, become the recorded proposer, and cancel it while pending.
    function test_propose_without_proposer_suffix_can_be_frontrun() public {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _noopProposal();
        string memory description = "no suffix";

        // `_voterB` front-runs `_voterA`'s identical proposal.
        vm.prank(_voterB);
        uint256 proposalId = _governor.propose(targets, values, calldatas, description);

        // `_voterA`'s own submission now reverts: the operation already exists under the same id.
        vm.prank(_voterA);
        vm.expectRevert();
        _governor.propose(targets, values, calldatas, description);

        // `_voterB`, as the recorded proposer, cancels it while pending; `_voterA` never got a say.
        vm.prank(_voterB);
        _governor.cancel(targets, values, calldatas, keccak256(bytes(description)));
        assertEq(uint8(_governor.state(proposalId)), uint8(IGovernor.ProposalState.Canceled));
    }

    /// @dev Pins the mitigation from the same doc section: a `#proposer=0x<address>` suffix restricts submission to
    /// that address, so the front-run in the test above is blocked.
    function test_propose_with_proposer_suffix_blocks_frontrunning() public {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _noopProposal();
        string memory description = string.concat("with suffix#proposer=", vm.toString(_voterA));

        vm.prank(_voterB);
        vm.expectRevert(
            abi.encodeWithSelector(IGovernor.GovernorRestrictedProposer.selector, _voterB), address(_governor)
        );
        _governor.propose(targets, values, calldatas, description);

        // The named proposer is unaffected.
        vm.prank(_voterA);
        _governor.propose(targets, values, calldatas, description);
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
