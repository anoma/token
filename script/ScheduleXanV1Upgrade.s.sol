// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.30;

import {Upgrades, Options} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Script} from "forge-std/Script.sol";

import {Parameters} from "../src/libs/Parameters.sol";
import {XanV1} from "../src/XanV1.sol";
import {DeployGovernance} from "./DeployGovernance.s.sol";

contract ScheduleXanV1Upgrade is Script {
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
        // implementation (which bakes the owner into its bytecode) is prepared. The governance-deploy script contract
        // holds and then renounces the temporary timelock admin, so it is the deployer.
        {
            DeployGovernance deployScript = new DeployGovernance();
            (governor, timelock, upgradeCouncil) =
                deployScript.deploy({token: proxy, councilMultisig: councilMultisig, deployer: address(deployScript)});
        }

        // Bind the freshly deployed timelock (as owner) and the vesting schedule into the V2 implementation bytecode
        // (the trusted step). The scheduled implementation address is fixed, so whoever later executes the
        // (permissionless) upgrade cannot change these via calldata.
        {
            Options memory opts;
            opts.constructorData = abi.encode(timelock, Parameters.VESTING_START, Parameters.VESTING_DURATION);
            implV2 = Upgrades.prepareUpgrade({contractName: "XanV2.sol:XanV2", opts: opts});
        }

        // Schedule the V1 to V2 upgrade through the V1 council.
        XanV1(proxy).scheduleCouncilUpgrade({impl: implV2});

        vm.stopBroadcast();
    }
}
