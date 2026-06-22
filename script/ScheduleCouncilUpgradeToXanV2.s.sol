// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.30;

import {Upgrades, Options} from "@openzeppelin/foundry-upgrades/Upgrades.sol";

import {Script} from "forge-std/Script.sol";

import {XanV1} from "../src/XanV1.sol";

contract ScheduleCouncilUpgradeToXanV2 is Script {
    function run(address proxy) public returns (address implV2) {
        Options memory opts;

        vm.startBroadcast();

        implV2 = Upgrades.prepareUpgrade({contractName: "XanV2.sol:XanV2", opts: opts});

        XanV1(proxy).scheduleCouncilUpgrade({impl: implV2});

        vm.stopBroadcast();
    }
}
