// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Upgrades, UnsafeUpgrades, Options} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Test} from "forge-std/Test.sol";

import {IXanV2} from "../src/interfaces/IXanV2.sol";
import {Parameters} from "../src/libs/Parameters.sol";
import {XanV2} from "../src/XanV2.sol";
import {XanV2Vesting} from "../src/XanV2Vesting.sol";

contract XanV2VestingInitializationTest is Test {
    address internal immutable _OWNER = makeAddr("owner");

    address internal _impl;
    XanV2Vesting internal _vestingProxy;

    function setUp() public {
        // `XanV2Vesting` reads only the schedule of the token here, so a `XanV2` implementation stands in for the proxy.
        IERC20 token = IERC20(
            address(
                new XanV2({
                    initialProxyOwner: _OWNER,
                    vestingStartTimestamp: Parameters.XAN_VESTING_START,
                    vestingDuration: Parameters.XAN_VESTING_DURATION
                })
            )
        );

        Options memory opts;
        opts.constructorData = abi.encode(token);
        _vestingProxy = XanV2Vesting(
            Upgrades.deployUUPSProxy({
                contractName: "XanV2Vesting.sol:XanV2Vesting",
                initializerData: abi.encodeCall(XanV2Vesting.initialize, (_OWNER)),
                opts: opts
            })
        );
        _impl = Upgrades.getImplementationAddress(address(_vestingProxy));
    }

    function test_initialize_emits_the_VestingScheduled_event() public {
        address predictedProxy = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));

        vm.expectEmit(predictedProxy);
        emit IXanV2.VestingScheduled({start: Parameters.XAN_VESTING_START, duration: Parameters.XAN_VESTING_DURATION});

        UnsafeUpgrades.deployUUPSProxy({
            impl: _impl, initializerData: abi.encodeCall(XanV2Vesting.initialize, (_OWNER))
        });
    }

    function test_initialize_reverts_when_called_again() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector, address(_vestingProxy));
        _vestingProxy.initialize({initialOwner: _OWNER});
    }

    function test_initialize_reverts_if_the_owner_is_the_zero_address() public {
        bytes memory initializerData = abi.encodeCall(XanV2Vesting.initialize, (address(0)));

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableInvalidOwner.selector, address(0)));
        UnsafeUpgrades.deployUUPSProxy({impl: _impl, initializerData: initializerData});
    }

    function test_initialize_sets_the_owner() public view {
        assertEq(_vestingProxy.owner(), _OWNER);
    }

    function test_initialize_adds_no_recipients() public view {
        assertEq(_vestingProxy.getRecipients().length, 0);
        assertEq(_vestingProxy.totalPrincipal(), 0);
    }
}
