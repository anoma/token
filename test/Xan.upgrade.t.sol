// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import {Upgrades, UnsafeUpgrades, Options} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Test} from "forge-std/Test.sol";

import {Xan} from "../src/Xan.sol";
import {XanV2} from "../test/mock/XanV2.sol";

contract UpgradeTest is Test {
    address internal _defaultSender;
    address internal _newImpl;
    Xan internal _xanProxy;

    function setUp() public {
        (, _defaultSender,) = vm.readCallers();

        // Deploy proxy and mint tokens for the `_defaultSender`.
        vm.startPrank(_defaultSender);
        _xanProxy = Xan(
            Upgrades.deployUUPSProxy({
                contractName: "Xan.sol:Xan",
                initializerData: abi.encodeCall(Xan.initialize, _defaultSender)
            })
        );

        Options memory opts;
        _newImpl = Upgrades.prepareUpgrade({contractName: "XanV2.sol:XanV2", opts: opts});

        // Lock the tokens for the `_defaultSender`.
        _xanProxy.lock(_xanProxy.unlockedBalanceOf(_defaultSender));

        vm.stopPrank();
    }

    function test_upgradeProxy() public {
        vm.prank(_defaultSender);
        _xanProxy.castVote(_newImpl);
        _xanProxy.startDelayPeriod(_newImpl);

        skip(_xanProxy.delayDuration());

        vm.expectEmit(address(_xanProxy));
        emit XanV2.Reinitialized();

        UnsafeUpgrades.upgradeProxy({
            proxy: address(_xanProxy),
            newImpl: _newImpl,
            data: abi.encodeCall(XanV2.initializeV2, ())
        });
    }

    function test_upgrade_old() public {
        // Vote for Implementation
        {
            vm.prank(_defaultSender);
            _xanProxy.castVote(_newImpl);
        }

        // Delay period
        {
            // Delay period hasn't started.
            vm.expectRevert(abi.encodeWithSelector(Xan.DelayPeriodNotStarted.selector, _newImpl), address(_xanProxy));
            _xanProxy.checkDelayPeriod(_newImpl);

            // Start the delay period
            _xanProxy.startDelayPeriod(_newImpl);

            // Delay period hasn't ended.
            vm.expectRevert(abi.encodeWithSelector(Xan.DelayPeriodNotEnded.selector, _newImpl), address(_xanProxy));
            _xanProxy.checkDelayPeriod(_newImpl);

            // Advance to the end of the delay period
            skip(_xanProxy.delayDuration());

            // Check that the delay has passed
            _xanProxy.checkDelayPeriod(_newImpl);
        }

        // Upgrade
        {
            _xanProxy.upgradeToAndCall({newImplementation: _newImpl, data: abi.encodeCall(XanV2.initializeV2, ())});

            // Check that the upgrade was successful.
            assertEq(_xanProxy.implementation(), _newImpl);
        }
    }
}
