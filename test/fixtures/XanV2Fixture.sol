// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {Upgrades, UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Test} from "forge-std/Test.sol";

import {Parameters} from "../../src/libs/Parameters.sol";
import {XanV1} from "../../src/XanV1.sol";
import {XanV2} from "../../src/XanV2.sol";
import {MockXanV2} from "../mocks/MockXanV2.sol";

/// @notice Shared fixture that deploys a fresh `XanV1` proxy (minting the whole supply to `_defaultSender`) and
/// upgrades it to `XanV2` via the production voter-body upgrade flow. The vesting schedule defaults to starting one
/// hour after the upgrade (`_upgradeTimestamp`); override `_vestingSchedule` to customize.
abstract contract XanV2Fixture is Test {
    address internal immutable _GOVERNANCE_COUNCIL = makeAddr("governanceCouncil");

    XanV1 internal _xanV1Proxy;
    XanV2 internal _xanV2Proxy;
    address internal _xanV1Impl;
    address internal _xanV2Impl;
    address internal _defaultSender;

    /// @notice The timestamp at which the V1→V2 upgrade executes in `setUp`. The voting total-supply checkpoint is
    /// seeded here, and the vesting schedule is chosen relative to it.
    uint48 internal _upgradeTimestamp;

    /// @notice The vesting schedule baked into the deployed `_xanV2Proxy`, captured in `setUp`.
    uint48 internal _vestingStart;
    uint48 internal _vestingMid;
    uint48 internal _vestingEnd;

    function setUp() public virtual {
        (, _defaultSender,) = vm.readCallers();

        // Deploy the proxy and mint the whole supply to the `_defaultSender`.
        _xanV1Proxy = XanV1(
            Upgrades.deployUUPSProxy({
                contractName: "XanV1.sol:XanV1",
                initializerData: abi.encodeCall(XanV1.initializeV1, (_defaultSender, _GOVERNANCE_COUNCIL))
            })
        );

        // The upgrade is executed once the voter-body scheduling delay elapses; the clock is not advanced before the
        // `vm.warp` below, so the upgrade lands at `now + DELAY_DURATION`. Fix that timestamp up front so the vesting
        // schedule can be chosen relative to it and the `vm.warp` can target it directly.
        _upgradeTimestamp = uint48(block.timestamp + Parameters.DELAY_DURATION);

        uint48 vestingDuration;
        (_vestingStart, vestingDuration) = _vestingSchedule();
        _vestingMid = _vestingStart + vestingDuration / 2;
        _vestingEnd = _vestingStart + vestingDuration;

        // Point the V2 mock at the locally deployed V1 implementation (the vesting principal is stored under it).
        // Captured before the in-place upgrade below, after which the proxy reports the V2 implementation instead.
        _xanV1Impl = _xanV1Proxy.implementation();
        _xanV2Impl = address(new MockXanV2(_xanV1Impl, _defaultSender, _vestingStart, vestingDuration));

        // Win the voter-body upgrade vote for `_xanV2Impl` and warp to the upgrade timestamp so it can be executed.
        vm.startPrank(_defaultSender);
        _xanV1Proxy.lock(_xanV1Proxy.unlockedBalanceOf(_defaultSender));
        _xanV1Proxy.castVote(_xanV2Impl);
        _xanV1Proxy.scheduleVoterBodyUpgrade();
        vm.stopPrank();

        vm.warp(_upgradeTimestamp);
        // Upgrade the proxy to V2.
        UnsafeUpgrades.upgradeProxy({
            proxy: address(_xanV1Proxy), newImpl: _xanV2Impl, data: abi.encodeCall(XanV2.reinitializeFromV1, ())
        });

        _xanV2Proxy = XanV2(address(_xanV1Proxy));
    }

    /// @notice The vesting `(start, duration)` baked into the deployed V2 implementation, anchored to the upgrade so
    /// the timeline is coherent: vesting begins one hour after the upgrade. Override to customize.
    function _vestingSchedule() internal view virtual returns (uint48 start, uint48 duration) {
        start = _upgradeTimestamp + 1 hours;
        duration = Parameters.VESTING_DURATION;
    }
}
