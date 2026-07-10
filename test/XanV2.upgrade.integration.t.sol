// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {DeployXanV1} from "../script/DeployXanV1.s.sol";
import {ScheduleXanV1Upgrade} from "../script/ScheduleXanV1Upgrade.s.sol";
import {UpgradeXanV1} from "../script/UpgradeXanV1.s.sol";
import {Parameters} from "../src/libs/Parameters.sol";
import {XanV1} from "../src/XanV1.sol";
import {XanV2} from "../src/XanV2.sol";

/// @notice Local integration test that runs the three production deployment scripts in sequence — `DeployXanV1`,
/// `ScheduleXanV1Upgrade`, and `UpgradeXanV1` — against fresh state, exactly as an operator would, to demonstrate
/// that the full V1->V2 upgrade flow works.
contract XanV2UpgradeIntegrationTest is Test {
    address internal immutable _MINT_RECIPIENT = makeAddr("mintRecipient");
    address internal immutable _COUNCIL_MULTISIG = makeAddr("councilMultisig");

    function test_scripts_drive_the_full_v1_to_v2_upgrade() public {
        // The scripts broadcast with no explicit sender, so every call they make originates from `DEFAULT_SENDER`.
        // The V1 governance council must therefore be `DEFAULT_SENDER` for `ScheduleXanV1Upgrade` to schedule the
        // upgrade, since `scheduleCouncilUpgrade` is `onlyCouncil`.
        address council = DEFAULT_SENDER;

        // 1. Deploy the XanV1 proxy.
        (address proxy, address implV1) =
            new DeployXanV1().run({initialMintRecipient: _MINT_RECIPIENT, council: council});
        uint256 supplyBefore = XanV1(proxy).totalSupply();
        assertEq(XanV1(proxy).implementation(), implV1, "proxy does not run V1");
        assertEq(XanV1(proxy).governanceCouncil(), council, "V1 council mismatch");

        // 2. Deploy governance, prepare the V2 implementation, and schedule the council upgrade in one script. The
        // timelock deployed here is baked into the V2 implementation bytecode as the token owner.
        (address implV2,, address timelock,) =
            new ScheduleXanV1Upgrade().run({proxy: proxy, councilMultisig: _COUNCIL_MULTISIG});

        (address scheduledImpl, uint48 endTime) = XanV1(proxy).scheduledCouncilUpgrade();
        assertEq(scheduledImpl, implV2, "council did not schedule the V2 implementation");
        assertEq(endTime, uint48(block.timestamp) + Parameters.DELAY_DURATION, "unexpected upgrade delay");

        // 3. Wait out the council delay, then execute the (permissionless) upgrade.
        vm.warp(endTime);
        address executed = new UpgradeXanV1().run({proxy: proxy});
        assertEq(executed, implV2, "executed a different implementation than scheduled");

        // 4. The proxy now runs XanV2 with the state baked into the implementation bytecode by `ScheduleXanV1Upgrade`:
        // the deployed timelock owns the token, the supply is conserved, and the vesting schedule matches the audited
        // `Parameters`.
        XanV2 tokenV2 = XanV2(proxy);
        assertEq(tokenV2.implementation(), implV2, "proxy not upgraded to V2");
        assertEq(tokenV2.owner(), timelock, "owner is not the deployed timelock");
        assertEq(tokenV2.totalSupply(), supplyBefore, "supply changed by the upgrade");
        assertEq(tokenV2.vestingStart(), Parameters.VESTING_START, "vesting start mismatch");
        assertEq(tokenV2.vestingEnd(), Parameters.VESTING_START + Parameters.VESTING_DURATION, "vesting end mismatch");
    }
}
