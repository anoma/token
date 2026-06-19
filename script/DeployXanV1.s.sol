// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.30;

import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";

import {Script} from "forge-std/Script.sol";

import {XanV1} from "../src/XanV1.sol";

contract Upgrade is Script {
    function run(address initialMintRecipient, address council) public returns (address proxy, address impl) {
        vm.startBroadcast();

        proxy = Upgrades.deployUUPSProxy({
            contractName: "XanV1.sol:XanV1",
            initializerData: abi.encodeCall(XanV1.initializeV1, (initialMintRecipient, council))
        });

        impl = XanV1(proxy).implementation();

        vm.stopBroadcast();
    }
}
