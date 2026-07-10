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

    /// @notice The V1 implementation address baked into `XanV2` as the storage key for every vesting principal
    /// (identical on Ethereum mainnet and Sepolia; mirrors `XanV2._XAN_V1_IMPLEMENTATION`).
    address internal constant _XAN_V1_IMPLEMENTATION = 0x03997b568FE70E91A53c458DC19dc29e0bC2735E;

    address internal immutable _INITIAL_OWNER = makeAddr("initialOwner");

    function tableNetworksTest_XanV2_council_scheduling_and_upgrade_succeeds_on_all_supported_networks(TestCase memory network)
        public
    {
        vm.createSelectFork(network.name);

        XanV1 proxy = XanV1(_XAN_PROXY);

        // The vesting principal is read from V1 storage keyed by the V1 implementation address baked into `XanV2`;
        // if the live implementation differed, every principal would silently read zero after the upgrade.
        assertEq(proxy.implementation(), _XAN_V1_IMPLEMENTATION, "live V1 implementation != baked constant");
        uint256 supplyBefore = proxy.totalSupply();

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

        // 4. Ensure that the upgrade to XanV2 was successful and installed the baked-in state: the owner comes from
        // the implementation bytecode (not from attacker-controllable calldata), the supply is conserved, and the
        // vesting schedule matches the audited parameters.
        XanV2 tokenV2 = XanV2(_XAN_PROXY);
        assertEq(tokenV2.implementation(), implV2, "proxy not upgraded to V2");
        assertEq(tokenV2.owner(), _INITIAL_OWNER, "owner not installed from the implementation bytecode");
        assertEq(tokenV2.totalSupply(), supplyBefore, "supply changed by the upgrade");
        assertEq(tokenV2.vestingStart(), Parameters.VESTING_START, "vesting start mismatch");
        assertEq(tokenV2.vestingEnd(), Parameters.VESTING_START + Parameters.VESTING_DURATION, "vesting end mismatch");
    }

    /// @notice The networks on which XanV1 is deployed.
    function fixtureNetwork() public pure returns (TestCase[] memory network) {
        network = new TestCase[](2);
        network[0] = TestCase({name: "mainnet"});
        network[1] = TestCase({name: "sepolia"});
    }
}
