// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.30;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {Script} from "forge-std/Script.sol";

import {Parameters} from "../src/libs/Parameters.sol";
import {XanGovernor} from "../src/XanGovernor.sol";
import {XanUpgradeCouncil} from "../src/XanUpgradeCouncil.sol";

/// @notice Deploys and wires the XAN governance stack: a `TimelockController` (the eventual token owner), the
/// `XanGovernor` driven by the token's `ERC20Votes`, and the `XanUpgradeCouncil` upgrade module. The timelock's roles
/// are granted to the governor and the council module, the executor role is opened, and the deployer's temporary admin
/// is renounced so only governance can change roles afterwards.
///
/// @dev Run this before scheduling the V1->V2 upgrade: the returned `timelock` is the address that must be baked into
/// the V2 implementation as its owner (i.e. set `Parameters.INITIAL_OWNER` to it).
contract DeployGovernance is Script {
    error InvalidTokenAddress();
    error InvalidCouncilAddress();

    function run(address token, address councilMultisig)
        public
        returns (address governor, address timelock, address upgradeCouncil)
    {
        require(token != address(0), InvalidTokenAddress());
        require(councilMultisig != address(0), InvalidCouncilAddress());

        vm.startBroadcast();

        address deployer = msg.sender;

        // 1. The timelock owns the token and executes accepted proposals.
        // The deployer is a temporary admin so the roles below can be wired; the timelock also self-administers, so
        // governance controls roles afterwards.
        address[] memory none = new address[](0);
        TimelockController timelockController = new TimelockController({
            minDelay: Parameters.DELAY_DURATION, proposers: none, executors: none, admin: deployer
        });

        // 2. Deploy the Xan Governor
        XanGovernor xanGovernor = new XanGovernor({
            xanToken: IVotes(token),
            timelockController: timelockController,
            initialVotingDelay: Parameters.VOTING_DELAY,
            initialVotingPeriod: Parameters.VOTING_PERIOD,
            initialProposalThreshold: Parameters.PROPOSAL_THRESHOLD,
            initialQuorumNumerator: Parameters.QUORUM_RATIO_NUMERATOR * 100 / Parameters.QUORUM_RATIO_DENOMINATOR
        });

        // 3. Deploy the security council module
        XanUpgradeCouncil xanUpgradeCouncil = new XanUpgradeCouncil({
            governor: IGovernor(address(xanGovernor)),
            timelock: timelockController,
            token: token,
            initialCouncil: councilMultisig,
            cancelBuffer: Parameters.COUNCIL_CANCEL_BUFFER
        });

        // 4. Wire roles:
        // * The governor and the council module can schedule and cancel.
        // * Anyone may execute after the delay.
        // * The council module constrains its scheduling to token upgrades and its cancellation to its own pending
        //   upgrade.
        bytes32 proposerRole = timelockController.PROPOSER_ROLE();
        bytes32 cancellerRole = timelockController.CANCELLER_ROLE();
        timelockController.grantRole(proposerRole, address(xanGovernor));
        timelockController.grantRole(cancellerRole, address(xanGovernor));
        timelockController.grantRole(proposerRole, address(xanUpgradeCouncil));
        timelockController.grantRole(cancellerRole, address(xanUpgradeCouncil));
        timelockController.grantRole(timelockController.EXECUTOR_ROLE(), address(0));

        // 5. Drop the deployer's admin; only the timelock (i.e. passed governance proposals) can change roles now.
        timelockController.renounceRole(timelockController.DEFAULT_ADMIN_ROLE(), deployer);

        vm.stopBroadcast();

        governor = address(xanGovernor);
        timelock = address(timelockController);
        upgradeCouncil = address(xanUpgradeCouncil);
    }
}
