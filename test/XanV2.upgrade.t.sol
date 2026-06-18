// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {Parameters} from "../src/libs/Parameters.sol";
import {XanV2} from "../src/XanV2.sol";
import {XanV2Fixture} from "./fixtures/XanV2Fixture.sol";
import {MockXanV2} from "./mocks/MockXanV2.sol";

contract XanV2UpgradeTest is XanV2Fixture {
    address internal immutable _OTHER = makeAddr("other");

    function test_authorizeUpgrade_reverts_if_the_caller_is_not_the_owner() public {
        address newImpl = address(new XanV2(msg.sender, Parameters.VESTING_START, Parameters.VESTING_DURATION));

        vm.prank(_OTHER);
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, _OTHER), address(_xanV2Proxy)
        );
        _xanV2Proxy.upgradeToAndCall(newImpl, "");
    }

    function test_authorizeUpgrade_upgrades_if_the_caller_is_the_owner() public {
        address newImpl = address(
            new MockXanV2(
                _xanV1Proxy.implementation(), msg.sender, Parameters.VESTING_START, Parameters.VESTING_DURATION
            )
        );

        vm.prank(_xanV2Proxy.owner());
        _xanV2Proxy.upgradeToAndCall(newImpl, "");

        assertEq(_xanV2Proxy.implementation(), newImpl);
    }

    function test_implementation_returns_the_current_implementation() public view {
        assertEq(_xanV2Proxy.implementation(), _xanV2Impl);
    }
}
