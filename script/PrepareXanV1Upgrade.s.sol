// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.30;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {Upgrades, Options} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Script} from "forge-std/Script.sol";

import {Parameters} from "../src/libs/Parameters.sol";
import {XanGovernor} from "../src/XanGovernor.sol";
import {XanUpgradeCouncil} from "../src/XanUpgradeCouncil.sol";
import {XanV1} from "../src/XanV1.sol";

/// @notice Deploys the XAN governance stack (timelock, `XanGovernor`, `XanUpgradeCouncil`), then prepares and schedules
/// the XanV1->V2 upgrade with the deployed timelock baked into the V2 implementation as the token owner.
contract ScheduleXanV1Upgrade is Script {
    error InvalidTokenAddress();
    error InvalidCouncilAddress();

    /// @notice Deploys the governance stack, then prepares and schedules the XanV1 to V2 upgrade in one flow.
    /// @param proxy The XanV1 proxy to upgrade.
    /// @param councilMultisig The initial upgrade-council multisig.
    /// @return implV2 The XanV2 implementation the upgrade installs.
    /// @return governor The deployed `XanGovernor`.
    /// @return timelock The deployed `TimelockController` — the token owner baked into `implV2`.
    /// @return upgradeCouncil The deployed `XanUpgradeCouncil` module.
    function run(address proxy, address councilMultisig)
        public
        returns (address implV2, address governor, address timelock, address upgradeCouncil)
    {
        vm.startBroadcast();

        // Deploy and wire governance first: its timelock becomes the token's owner, so it must exist before the V2
        // implementation (which bakes the owner into its bytecode) is prepared. The broadcast sender runs the wiring:
        // it holds and then renounces the temporary timelock admin, so it is the deployer. `tx.origin` is the broadcast
        // sender both under `forge script` and in tests (unlike `msg.sender`).
        {
            // solhint-disable-next-line avoid-tx-origin
            address deployer = tx.origin;
            (governor, timelock, upgradeCouncil) =
                deployGovernance({token: proxy, councilMultisig: councilMultisig, deployer: deployer});
        }

        // Prepare the XanV2 upgrade implementation. The freshly deployed timelock (as owner) and the vesting schedule
        // are baked into the V2 implementation bytecode by the constructor, so they cannot be changed.
        {
            Options memory opts;
            opts.constructorData = abi.encode(timelock, Parameters.VESTING_START, Parameters.VESTING_DURATION);
            implV2 = Upgrades.prepareUpgrade({contractName: "XanV2.sol:XanV2", opts: opts});
        }

        // Schedule the V1 to V2 upgrade through the V1 council.
        {
            XanV1(proxy).scheduleCouncilUpgrade({impl: implV2});
        }

        vm.stopBroadcast();
    }

    /// @notice Deploys and wires the XAN governance stack: a `TimelockController` (the eventual token owner), the
    /// `XanGovernor` driven by the token's `ERC20Votes`, and the `XanUpgradeCouncil` module. The timelock's roles
    /// are granted to the governor and the council module, the executor role is opened, and the deployer's temporary
    /// admin is renounced so only governance can change roles afterwards.
    /// @param token The XAN token proxy.
    /// @param councilMultisig The initial council multisig.
    /// @param deployer The account sending the deployment transactions (it holds, and then renounces, the temporary
    /// timelock admin).
    /// @return governor The deployed `XanGovernor`.
    /// @return timelock The deployed `TimelockController` (the eventual token owner).
    /// @return upgradeCouncil The deployed `XanUpgradeCouncil` module.
    function deployGovernance(address token, address councilMultisig, address deployer)
        public
        returns (address governor, address timelock, address upgradeCouncil)
    {
        require(token != address(0), InvalidTokenAddress());
        require(councilMultisig != address(0), InvalidCouncilAddress());

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

        // 3. Deploy the upgrade council module; the timelock is its `Ownable` owner and rotates the council.
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

        governor = address(xanGovernor);
        timelock = address(timelockController);
        upgradeCouncil = address(xanUpgradeCouncil);
    }
}
