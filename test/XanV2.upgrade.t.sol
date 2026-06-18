// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Upgrades, UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Test} from "forge-std/Test.sol";

import {XanV2} from "../src/drafts/XanV2.sol";
import {Parameters} from "../src/libs/Parameters.sol";
import {XanV1} from "../src/XanV1.sol";
import {MockXanV2} from "./mocks/XanV2.m.sol";

contract XanV2UpgradeTest is Test {
    XanV1 internal _xanV1Proxy;
    XanV2 internal _xanV2Proxy;
    address internal _xanV2Impl;
    address internal _defaultSender;
    address internal immutable _OTHER = makeAddr("other");
    address internal immutable _GOVERNANCE_COUNCIL = makeAddr("governanceCouncil");

    function setUp() public {
        (, _defaultSender,) = vm.readCallers();

        // Deploy proxy and mint tokens for the `_defaultSender`.
        _xanV1Proxy = XanV1(
            Upgrades.deployUUPSProxy({
                contractName: "XanV1.sol:XanV1",
                initializerData: abi.encodeCall(XanV1.initializeV1, (_defaultSender, _GOVERNANCE_COUNCIL))
            })
        );

        // Point the V2 mock at the locally deployed V1 implementation (the vesting principal is stored under it).
        _xanV2Impl = address(new MockXanV2(_xanV1Proxy.implementation()));

        _winUpgradeVoteForV2Impl(_xanV1Proxy);

        skip(Parameters.DELAY_DURATION);

        UnsafeUpgrades.upgradeProxy({
            proxy: address(_xanV1Proxy),
            newImpl: _xanV2Impl,
            data: abi.encodeCall(XanV2.reinitializeFromV1, (msg.sender))
        });

        _xanV2Proxy = XanV2(address(_xanV1Proxy));
    }

    function test_authorizeUpgrade_reverts_if_the_caller_is_not_the_owner() public {
        address newImpl = address(new XanV2());

        vm.prank(_OTHER);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, _OTHER));
        _xanV2Proxy.upgradeToAndCall(newImpl, "");
    }

    function test_authorizeUpgrade_upgrades_if_the_caller_is_the_owner() public {
        address newImpl = address(new MockXanV2(_xanV1Proxy.implementation()));

        vm.prank(_xanV2Proxy.owner());
        _xanV2Proxy.upgradeToAndCall(newImpl, "");

        assertEq(_xanV2Proxy.implementation(), newImpl);
    }

    function _winUpgradeVoteForV2Impl(XanV1 xanV1Proxy) internal {
        vm.startPrank(_defaultSender);
        xanV1Proxy.lock(xanV1Proxy.unlockedBalanceOf(_defaultSender));
        xanV1Proxy.castVote(_xanV2Impl);
        xanV1Proxy.scheduleVoterBodyUpgrade();
        vm.stopPrank();
        skip(Parameters.DELAY_DURATION);
    }
}
