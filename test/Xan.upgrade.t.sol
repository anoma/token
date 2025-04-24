// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import {Upgrades, UnsafeUpgrades, Options} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Test} from "forge-std/Test.sol";

import {Parameters} from "../src/libs/Parameters.sol";
import {XanV1} from "../src/XanV1.sol";
import {XanV2} from "../test/mocks/XanV2.m.sol";

contract UpgradeTest is Test {
    address internal _defaultSender;
    address internal _newImpl;
    XanV1 internal _xanProxy;

    function setUp() public {
        (, _defaultSender,) = vm.readCallers();

        // Deploy proxy and mint tokens for the `_defaultSender`.
        vm.startPrank(_defaultSender);
        _xanProxy = XanV1(
            Upgrades.deployUUPSProxy({
                contractName: "XanV1.sol:XanV1",
                initializerData: abi.encodeCall(XanV1.initialize, _defaultSender)
            })
        );

        Options memory opts;
        _newImpl = Upgrades.prepareUpgrade({contractName: "XanV2.m.sol:XanV2", opts: opts});

        // Lock the tokens for the `_defaultSender`.
        _xanProxy.lock(_xanProxy.unlockedBalanceOf(_defaultSender));

        vm.stopPrank();
    }

    function test_upgradeProxy() public {
        vm.prank(_defaultSender);
        _xanProxy.castVote(_newImpl);
        _xanProxy.startDelayPeriod(_newImpl);

        skip(Parameters.DELAY_DURATION);

        vm.expectEmit(address(_xanProxy));
        emit XanV2.Reinitialized();

        UnsafeUpgrades.upgradeProxy({
            proxy: address(_xanProxy),
            newImpl: _newImpl,
            data: abi.encodeCall(XanV2.initializeV2, ())
        });
    }

    // TODO move into separate test
    /*
    function test_upgrade_old() public {
        // Vote for Implementation
        {
            vm.prank(_defaultSender);
            _xanProxy.castVote(_newImpl);
        }

        // Delay period
        {
            // Delay period hasn't started.
            vm.expectRevert(abi.encodeWithSelector(XanV1.DelayPeriodNotStarted.selector, _newImpl), address(_xanProxy));
            _xanProxy.checkDelayPeriod(_newImpl);

            // Start the delay period
            _xanProxy.startDelayPeriod(_newImpl);

            // Delay period hasn't ended.
            vm.expectRevert(abi.encodeWithSelector(XanV1.DelayPeriodNotEnded.selector, _newImpl), address(_xanProxy));
            _xanProxy.checkDelayPeriod(_newImpl);

            // Advance to the end of the delay period
            skip(Parameters.DELAY_DURATION);

            // Check that the delay has passed
            _xanProxy.checkDelayPeriod(_newImpl);
        }

        // Upgrade
        {
            _xanProxy.upgradeToAndCall({newImplementation: _newImpl, data: abi.encodeCall(XanV2.initializeV2, ())});

            // Check that the upgrade was successful.
            assertEq(_xanProxy.implementation(), _newImpl);
        }
    }*/
}
