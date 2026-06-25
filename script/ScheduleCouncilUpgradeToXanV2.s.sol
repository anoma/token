// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.30;

import {Upgrades, Options} from "@openzeppelin/foundry-upgrades/Upgrades.sol";

import {Script} from "forge-std/Script.sol";

import {XanV1} from "../src/XanV1.sol";
import {Parameters} from "../src/libs/Parameters.sol";

contract ScheduleCouncilUpgradeToXanV2 is Script {
    function run(address proxy, address owner) public returns (address implV2) {
        Options memory opts;

        // Bind the owner and vesting schedule into the implementation bytecode at deployment (the trusted step). The
        // scheduled implementation address is fixed, so whoever later executes the (permissionless) upgrade cannot
        // change these via calldata. Always use the `Parameters` constants so the vesting schedule cannot be picked
        // wrong.
        opts.constructorData = abi.encode(owner, Parameters.VESTING_START, Parameters.VESTING_DURATION);

        vm.startBroadcast();

        implV2 = Upgrades.prepareUpgrade({contractName: "XanV2.sol:XanV2", opts: opts});

        XanV1(proxy).scheduleCouncilUpgrade({impl: implV2});

        vm.stopBroadcast();
    }
}
