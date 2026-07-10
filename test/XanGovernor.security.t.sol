// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {
    GovernorVotesQuorumFraction
} from "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {XanGovernorFixture} from "./fixtures/XanGovernorFixture.sol";

/// @notice Pins the governance-only gates the layer's security rests on: `relay` (the voter body's instrument for
/// cancelling council upgrades), the governor's settings, and the timelock's delay are reachable only through a
/// passed proposal — never directly.
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

    /// @notice The quorum — the parameter the council design's capture-cost argument rests on (ADR-0007) — moves
    /// only through a passed proposal, and a passed proposal can move it.
    function test_quorum_changes_only_through_a_passed_proposal() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(_governor);
        calldatas[0] = abi.encodeCall(GovernorVotesQuorumFraction.updateQuorumNumerator, (30));

        _passProposal({targets: targets, values: values, calldatas: calldatas, description: "lower the quorum to 30%"});

        assertEq(_governor.quorumNumerator(), 30);
    }
}
