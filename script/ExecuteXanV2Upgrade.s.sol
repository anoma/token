// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.30;

import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";

import {Script} from "forge-std/Script.sol";

import {XanV1} from "../src/XanV1.sol";
import {XanV2} from "../src/XanV2.sol";

contract ExecuteXanV2Upgrade is Script {
    error ZeroImplementationV2NotAllowed();

    function run(address proxy) public returns (address implementationV2) {
        uint48 endTime;

        (implementationV2, endTime) = XanV1(proxy).scheduledCouncilUpgrade();

        require(implementationV2 != address(0), ZeroImplementationV2NotAllowed());
        require(endTime <= Time.timestamp(), XanV1.DelayPeriodNotEnded({endTime: endTime}));

        vm.startBroadcast();

        // The owner and vesting start are baked into `implV2` at deployment (see `PrepareXanV2Upgrade`),
        // so `reinitializeFromV1` takes no arguments and executing this upgrade cannot influence them.
        UnsafeUpgrades.upgradeProxy({
            proxy: proxy, newImpl: implementationV2, data: abi.encodeCall(XanV2.reinitializeFromV1, ())
        });

        vm.stopBroadcast();
    }
}
