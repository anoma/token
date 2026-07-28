// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.30;

import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";

import {Script} from "forge-std/Script.sol";

import {XanV1} from "../src/XanV1.sol";

/// @notice Deploys the XanV1 implementation behind a UUPS proxy and initializes it with the initial mint recipient
/// (the token distributor) and the governance council.
contract DeployXanV1 is Script {
    function run(address initialMintRecipient, address council) public returns (address proxy, address implementation) {
        vm.startBroadcast();

        proxy = Upgrades.deployUUPSProxy({
            contractName: "XanV1.sol:XanV1",
            initializerData: abi.encodeCall(XanV1.initializeV1, (initialMintRecipient, council))
        });

        implementation = XanV1(proxy).implementation();

        vm.stopBroadcast();
    }
}
