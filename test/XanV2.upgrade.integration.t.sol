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
    struct TestCase {
        string name;
    }

    /// @notice The live XAN proxy address (identical on Ethereum mainnet and Sepolia).
    address internal constant _XAN_PROXY = 0xCEDbEA37C8872c4171259Cdfd5255CB8923Cf8e7;

    address internal immutable _INITIAL_OWNER = makeAddr("initialOwner");

    function tableNetworksTest_XanV2_council_scheduling_and_upgrade_succeeds_on_all_supported_networks(TestCase memory network)
        public
    {
        vm.createSelectFork(network.name);

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
    function fixtureNetwork() public pure returns (TestCase[] memory network) {
        network = new TestCase[](2);
        network[0] = TestCase({name: "mainnet"});
        network[1] = TestCase({name: "sepolia"});
    }
}
