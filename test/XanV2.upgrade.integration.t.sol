// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {Upgrades, UnsafeUpgrades, Options} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Test} from "forge-std/Test.sol";

import {Parameters} from "../src/libs/Parameters.sol";
import {XanV1} from "../src/XanV1.sol";
import {XanV2} from "../src/XanV2.sol";

/// @notice Fork integration tests that exercise the upgrade of the live XAN proxies on:
/// * Mainnet
/// * Sepolia
contract XanV2UpgradeIntegrationTest is Test {
    /// @notice The live XAN proxy address (identical on Ethereum mainnet and Sepolia).
    address internal constant _XAN_PROXY = 0xCEDbEA37C8872c4171259Cdfd5255CB8923Cf8e7;

    address internal immutable _INITIAL_OWNER = makeAddr("initialOwner");

    function test_v1_council_scheduled_upgrade_to_V2_succeeds_on_all_supported_networks() public {
        string[] memory networks = _supportedNetworks();

        for (uint256 i = 0; i < networks.length; ++i) {
            _scheduleCouncilUpgradeAndExecute(networks[i]);
        }
    }

    /// @notice Schedules the XanV2 upgrade through the XanV1 governance council and executes it on a given network fork.
    /// @param network The network to fork and run the upgrade on.
    function _scheduleCouncilUpgradeAndExecute(string memory network) internal {
        vm.createSelectFork(network);

        XanV1 proxy = XanV1(_XAN_PROXY);

        // 1. Prepare and schedule the XanV2 implementation.
        Options memory opts;
        opts.constructorData = abi.encode(_INITIAL_OWNER, Parameters.VESTING_START, Parameters.VESTING_DURATION);
        address implV2 = Upgrades.prepareUpgrade({contractName: "XanV2.sol:XanV2", opts: opts});

        // 2. Schedule the council upgrade as the governance council.
        vm.prank(proxy.governanceCouncil());
        proxy.scheduleCouncilUpgrade({impl: implV2});

        (address scheduledImpl, uint48 endTime) = proxy.scheduledCouncilUpgrade();
        assertEq(scheduledImpl, implV2, "council did not schedule the implementation");

        // 3. Wait out the council delay and execute the upgrade permissionlessly.
        vm.warp(endTime);
        UnsafeUpgrades.upgradeProxy({
            proxy: _XAN_PROXY, newImpl: implV2, data: abi.encodeCall(XanV2.reinitializeFromV1, ())
        });

        // 4. Ensure that the upgrade to XanV2 was successful.
        assertEq(XanV2(_XAN_PROXY).implementation(), implV2, "proxy not upgraded to V2");
    }

    /// @notice The networks on which XanV1 is deployed.
    /// @return networks The list of network names to fork.
    function _supportedNetworks() internal pure returns (string[] memory networks) {
        networks = new string[](2);
        networks[0] = "mainnet";
        networks[1] = "sepolia";
    }
}
