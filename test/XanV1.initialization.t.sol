// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {Upgrades, UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";

import {Test} from "forge-std/Test.sol";

import {Parameters} from "../src/libs/Parameters.sol";
import {XanV1} from "../src/XanV1.sol";

contract XanV1InitializationTest is Test {
    address internal immutable _COUNCIL = makeAddr("council");

    address internal _defaultSender;
    XanV1 internal _xanProxy;
    bytes internal _defaultInitializeV1Calldata;

    function setUp() public {
        (, _defaultSender,) = vm.readCallers();

        _defaultInitializeV1Calldata = abi.encodeCall(XanV1.initializeV1, (_defaultSender, _COUNCIL));

        _xanProxy = XanV1(
            Upgrades.deployUUPSProxy({contractName: "XanV1.sol:XanV1", initializerData: _defaultInitializeV1Calldata})
        );
    }

    function test_implementation_points_to_the_correct_implementation() public {
        address impl = address(new XanV1());

        XanV1 proxy = XanV1(UnsafeUpgrades.deployUUPSProxy({impl: impl, initializerData: _defaultInitializeV1Calldata}));

        assertEq(proxy.implementation(), impl);
    }

    function test_initialize_mints_the_supply_for_the_specified_owner() public view {
        assertEq(_xanProxy.unlockedBalanceOf(_defaultSender), _xanProxy.totalSupply());
    }

    function test_initialize_mints_the_expected_supply_amounting_to_10_billion_tokens() public view {
        uint256 expectedTokens = 10 ** 10;

        // Consider the decimals for the expected supply.
        uint256 expectedSupply = expectedTokens * (10 ** _xanProxy.decimals());

        assertEq(Parameters.SUPPLY, expectedSupply);
        assertEq(_xanProxy.totalSupply(), expectedSupply);
    }
}
