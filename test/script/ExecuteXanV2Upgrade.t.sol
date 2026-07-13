// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Test} from "forge-std/Test.sol";

import {ExecuteXanV2Upgrade} from "../../script/ExecuteXanV2Upgrade.s.sol";
import {XanV1} from "../../src/XanV1.sol";

contract ExecuteXanV2UpgradeTest is Test {
    address internal immutable _COUNCIL = makeAddr("council");

    ExecuteXanV2Upgrade internal _script;
    address internal _proxy;

    function setUp() public {
        _proxy = Upgrades.deployUUPSProxy(
            "XanV1.sol:XanV1", abi.encodeCall(XanV1.initializeV1, (makeAddr("mintRecipient"), _COUNCIL))
        );
        _script = new ExecuteXanV2Upgrade();
    }

    function test_run_reverts_if_no_upgrade_is_scheduled() public {
        vm.expectRevert(ExecuteXanV2Upgrade.ZeroImplementationV2NotAllowed.selector, address(_script));
        _script.run({proxy: _proxy});
    }

    function test_run_reverts_before_the_delay_has_elapsed() public {
        vm.prank(_COUNCIL);
        XanV1(_proxy).scheduleCouncilUpgrade({impl: makeAddr("implV2")});
        (, uint48 endTime) = XanV1(_proxy).scheduledCouncilUpgrade();

        vm.expectRevert(abi.encodeWithSelector(XanV1.DelayPeriodNotEnded.selector, endTime), address(_script));
        _script.run({proxy: _proxy});
    }
}
