// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.30;

import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";

import {Script} from "forge-std/Script.sol";

import {XanV2} from "../src/drafts/XanV2.sol";

contract Upgrade is Script {
    function run(address owner) public {
        vm.startBroadcast();

        Upgrades.upgradeProxy({
            proxy: _XAN_PROXY, contractName: "XanV2.sol:XanV2", data: abi.encodeCall(XanV2.reinitializeFromV1, (owner))
        });

        vm.stopBroadcast();
    }
}
