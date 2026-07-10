// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Test} from "forge-std/Test.sol";

import {UpgradeXanV1} from "../../script/UpgradeXanV1.s.sol";
import {XanV1} from "../../src/XanV1.sol";

/// @notice Covers the pre-flight guards `UpgradeXanV1` checks before broadcasting the upgrade. The happy path is
/// exercised by the upgrade integration and e2e tests.
contract UpgradeXanV1Test is Test {
    address internal immutable _COUNCIL = makeAddr("council");

    UpgradeXanV1 internal _script;
    address internal _proxy;

    function setUp() public {
        _proxy = Upgrades.deployUUPSProxy(
            "XanV1.sol:XanV1", abi.encodeCall(XanV1.initializeV1, (makeAddr("mintRecipient"), _COUNCIL))
        );
        _script = new UpgradeXanV1();
    }

    /// @notice `run` reverts when no council upgrade has been scheduled.
    function test_run_reverts_if_no_upgrade_is_scheduled() public {
        vm.expectRevert(UpgradeXanV1.ZeroImplementationV2NotAllowed.selector, address(_script));
        _script.run({proxy: _proxy});
    }

    /// @notice `run` reverts when the scheduled council delay has not yet elapsed.
    function test_run_reverts_before_the_delay_has_elapsed() public {
        vm.prank(_COUNCIL);
        XanV1(_proxy).scheduleCouncilUpgrade({impl: makeAddr("implV2")});
        (, uint48 endTime) = XanV1(_proxy).scheduledCouncilUpgrade();

        vm.expectRevert(abi.encodeWithSelector(XanV1.DelayPeriodNotEnded.selector, endTime), address(_script));
        _script.run({proxy: _proxy});
    }
}
