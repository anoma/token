// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.30;

import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";

import {Script} from "forge-std/Script.sol";

import {XanV2} from "../src/drafts/XanV2.sol";

contract Upgrade is Script {
    address internal constant _XAN_PROXY = address(0);
    address internal constant _PROTOCOL_ADAPTER = address(0);
    bytes32 internal constant _CALLDATA_CARRIER_LOGIC_REF = bytes32(0);

    function run(address owner) public {
        vm.startBroadcast();

        Upgrades.upgradeProxy({
            proxy: _XAN_PROXY, contractName: "XanV2.sol:XanV2", data: abi.encodeCall(XanV2.reinitializeFromV1, (owner))
        });

        vm.stopBroadcast();
    }
}
