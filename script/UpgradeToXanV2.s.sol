// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.30;

import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";

import {Script} from "forge-std/Script.sol";

import {XanV2} from "../src/drafts/XanV2.sol";
import {XanV1} from "../src/XanV1.sol";

contract UpgradeToXanV2 is Script {
    function run(address proxy) public returns (address newImplementation) {
        (address implV2, uint48 endTime) = XanV1(proxy).scheduledCouncilUpgrade();

        require(endTime <= Time.timestamp(), XanV1.DelayPeriodNotEnded({endTime: endTime}));

        vm.startBroadcast();

        // The owner and vesting start are baked into `implV2` at deployment (see `ScheduleCouncilUpgradeToXanV2`),
        // so `reinitializeFromV1` takes no arguments and executing this upgrade cannot influence them.
        UnsafeUpgrades.upgradeProxy({proxy: proxy, newImpl: implV2, data: abi.encodeCall(XanV2.reinitializeFromV1, ())});

        vm.stopBroadcast();

        newImplementation = XanV2(proxy).implementation();
    }
}
