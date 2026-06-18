// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Upgrades, UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Test} from "forge-std/Test.sol";

import {IXanV2} from "../src/interfaces/IXanV2.sol";
import {Parameters} from "../src/libs/Parameters.sol";
import {XanV1} from "../src/XanV1.sol";
import {XanV2} from "../src/XanV2.sol";
import {MockXanV2} from "./mocks/MockXanV2.sol";

contract XanV2ReinitializationTest is Test {
    address internal immutable _COUNCIL = makeAddr("council");
    address internal immutable _INITIAL_OWNER = makeAddr("owner");

    address internal _defaultSender;

    XanV1 internal _xanV1Proxy;
    XanV2 internal _xanV2Proxy;
    address internal _xanV2Impl;

    function setUp() public {
        (, _defaultSender,) = vm.readCallers();

        (_xanV1Proxy, _xanV2Impl) = _deployV1AndPrepareUpgrade();

        UnsafeUpgrades.upgradeProxy({
            proxy: address(_xanV1Proxy), newImpl: _xanV2Impl, data: abi.encodeCall(XanV2.reinitializeFromV1, ())
        });

        _xanV2Proxy = XanV2(address(_xanV1Proxy));
    }

    function test_reinitializeFromV1_emits_the_VestingScheduled_event() public {
        (XanV1 v1Proxy, address v2Impl) = _deployV1AndPrepareUpgrade();

        vm.expectEmit(address(v1Proxy));
        emit IXanV2.VestingScheduled({start: Parameters.VESTING_START, duration: Parameters.VESTING_DURATION});

        UnsafeUpgrades.upgradeProxy({
            proxy: address(v1Proxy), newImpl: v2Impl, data: abi.encodeCall(XanV2.reinitializeFromV1, ())
        });
    }

    function test_reinitializeFromV1_reverts_when_called_again() public {
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector), address(_xanV2Proxy));
        _xanV2Proxy.reinitializeFromV1();
    }

    function test_reinitializeFromV1_sets_the_owner() public view {
        assertEq(_xanV2Proxy.owner(), _INITIAL_OWNER);
    }

    /// @notice `reinitializeFromV1` must take no arguments. The upgrade can be executed by anyone once the V1 delay
    /// elapses, so any argument would be attacker-controlled; the owner and vesting schedule are bound into the
    /// implementation bytecode instead. This variant pins the selector to the no-argument signature, so adding a
    /// parameter changes `XanV2.reinitializeFromV1.selector` and fails the assertion.
    function test_reinitializeFromV1_takes_no_arguments() public pure {
        assertEq(
            bytes32(XanV2.reinitializeFromV1.selector),
            bytes32(bytes4(keccak256("reinitializeFromV1()"))),
            "reinitializeFromV1 must take no arguments"
        );
    }

    /// @notice Deploys a V1 proxy, mints to `_defaultSender`, and wins a voter-body upgrade vote for a freshly
    /// deployed V2 implementation so the proxy is ready to be upgraded.
    function _deployV1AndPrepareUpgrade() internal returns (XanV1 v1Proxy, address v2Impl) {
        v1Proxy = XanV1(
            Upgrades.deployUUPSProxy({
                contractName: "XanV1.sol:XanV1",
                initializerData: abi.encodeCall(XanV1.initializeV1, (_defaultSender, _COUNCIL))
            })
        );

        // Point the V2 mock at the locally deployed V1 implementation (the vesting principal is stored under it).
        v2Impl = address(
            new MockXanV2(
                v1Proxy.implementation(), _INITIAL_OWNER, Parameters.VESTING_START, Parameters.VESTING_DURATION
            )
        );

        vm.startPrank(_defaultSender);
        v1Proxy.lock(v1Proxy.unlockedBalanceOf(_defaultSender));
        v1Proxy.castVote(v2Impl);
        v1Proxy.scheduleVoterBodyUpgrade();
        vm.stopPrank();

        skip(Parameters.DELAY_DURATION);
    }
}
