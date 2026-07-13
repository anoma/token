// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {GovernorTimelockControl} from "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {
    GovernorVotesQuorumFraction
} from "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

/// @title XanGovernor
/// @author Anoma Foundation, 2026
/// @notice An OpenZeppelin `Governor` DAO driven by the `ERC20Votes`-compatible XAN token.
/// @custom:security-contact security@anoma.foundation
contract XanGovernor is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl
{
    /// @notice Deploys the governor.
    /// @param xanToken The `ERC20Votes`-compatible voting XAN token (the XAN proxy).
    /// @param timelockController The timelock controller that queues and executes accepted proposals.
    /// @param initialVotingDelay The delay (in seconds) between proposal creation and the start of voting.
    /// @param initialVotingPeriod The duration (in seconds) of the voting window.
    /// @param initialProposalThreshold The minimum voting power required to create a proposal.
    /// @param initialQuorumNumerator The quorum as a percentage of the total voting supply (e.g. `50` for 50%).
    constructor(
        IVotes xanToken,
        TimelockController timelockController,
        uint48 initialVotingDelay,
        uint32 initialVotingPeriod,
        uint256 initialProposalThreshold,
        uint256 initialQuorumNumerator
    )
        Governor("XanGovernor")
        GovernorSettings(initialVotingDelay, initialVotingPeriod, initialProposalThreshold)
        GovernorVotes(xanToken)
        GovernorVotesQuorumFraction(initialQuorumNumerator)
        GovernorTimelockControl(timelockController)
    {}

    // The following functions are overrides required by Solidity.

    /// @inheritdoc IGovernor
    function votingDelay() public view override(Governor, GovernorSettings) returns (uint256 delay) {
        delay = super.votingDelay();
    }

    /// @inheritdoc IGovernor
    function votingPeriod() public view override(Governor, GovernorSettings) returns (uint256 period) {
        period = super.votingPeriod();
    }

    /// @inheritdoc IGovernor
    function quorum(uint256 timepoint)
        public
        view
        override(Governor, GovernorVotesQuorumFraction)
        returns (uint256 quorumVotes)
    {
        quorumVotes = super.quorum(timepoint);
    }

    /// @inheritdoc IGovernor
    function state(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (ProposalState proposalState)
    {
        proposalState = super.state(proposalId);
    }

    /// @inheritdoc IGovernor
    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (bool needsQueuing)
    {
        needsQueuing = super.proposalNeedsQueuing(proposalId);
    }

    /// @inheritdoc IGovernor
    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256 threshold) {
        threshold = super.proposalThreshold();
    }

    /// @inheritdoc GovernorVotes
    /// @dev Pins the clock to the timestamp rather than inheriting `GovernorVotes`'s adaptive clock.
    function clock() public view virtual override(Governor, GovernorVotes) returns (uint48 timepoint) {
        timepoint = Time.timestamp();
    }

    /* solhint-disable func-name-mixedcase */

    /// @inheritdoc GovernorVotes
    /// @dev Pins the clock mode to timestamp rather than inheriting `GovernorVotes`'s adaptive clock mode.
    function CLOCK_MODE() public pure virtual override(Governor, GovernorVotes) returns (string memory mode) {
        mode = "mode=timestamp";
    }

    /* solhint-enable func-name-mixedcase */

    /// @notice Queues the accepted proposal's operations into the timelock.
    /// @param proposalId The identifier of the proposal.
    /// @param targets The addresses the proposal calls.
    /// @param values The native token values forwarded with each call.
    /// @param calldatas The calldata of each call.
    /// @param descriptionHash The hash of the proposal description.
    /// @return queuedAt The timestamp at which the queued operations become executable.
    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint48 queuedAt) {
        queuedAt = super._queueOperations({
            proposalId: proposalId,
            targets: targets,
            values: values,
            calldatas: calldatas,
            descriptionHash: descriptionHash
        });
    }

    /// @notice Executes the proposal's operations through the timelock.
    /// @param proposalId The identifier of the proposal.
    /// @param targets The addresses the proposal calls.
    /// @param values The native token values forwarded with each call.
    /// @param calldatas The calldata of each call.
    /// @param descriptionHash The hash of the proposal description.
    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._executeOperations({
            proposalId: proposalId,
            targets: targets,
            values: values,
            calldatas: calldatas,
            descriptionHash: descriptionHash
        });
    }

    /// @notice Cancels a proposal, also cancelling it in the timelock if it was already queued.
    /// @param targets The addresses the proposal calls.
    /// @param values The native token values forwarded with each call.
    /// @param calldatas The calldata of each call.
    /// @param descriptionHash The hash of the proposal description.
    /// @return proposalId The identifier of the cancelled proposal.
    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256 proposalId) {
        proposalId = super._cancel({
            targets: targets, values: values, calldatas: calldatas, descriptionHash: descriptionHash
        });
    }

    /// @notice Returns the address that executes accepted proposals (the timelock).
    /// @return executor The proposal executor.
    function _executor() internal view override(Governor, GovernorTimelockControl) returns (address executor) {
        executor = super._executor();
    }
}
