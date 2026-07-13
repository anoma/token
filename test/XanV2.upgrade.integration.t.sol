// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {Test} from "forge-std/Test.sol";

import {DeployXanV1} from "../script/DeployXanV1.s.sol";
import {PrepareXanV1Upgrade} from "../script/PrepareXanV1Upgrade.s.sol";
import {UpgradeXanV1} from "../script/UpgradeXanV1.s.sol";
import {Parameters} from "../src/libs/Parameters.sol";
import {XanGovernor} from "../src/XanGovernor.sol";
import {XanV1} from "../src/XanV1.sol";
import {XanV2} from "../src/XanV2.sol";

/// @notice Local integration test that runs the production deployment scripts — `DeployXanV1`, `PrepareXanV1Upgrade`,
/// and `UpgradeXanV1` — plus the V1 council's `scheduleCouncilUpgrade` (a Safe transaction in production), against
/// fresh state, to demonstrate that the full V1->V2 upgrade flow works.
contract XanV2UpgradeIntegrationTest is Test {
    address internal immutable _MINT_RECIPIENT = makeAddr("mintRecipient");
    // The council multisig (a Safe{Wallet}) is both the V1 governance council — which schedules the upgrade — and the
    // `XanUpgradeCouncil`.
    address internal immutable _COUNCIL_MULTISIG = makeAddr("councilMultisig");

    function test_scripts_drive_the_full_v1_to_v2_upgrade() public {
        // 1. Deploy the XanV1 proxy governed by the council multisig.
        (address proxy, address implV1) =
            new DeployXanV1().run({initialMintRecipient: _MINT_RECIPIENT, council: _COUNCIL_MULTISIG});
        uint256 supplyBefore = XanV1(proxy).totalSupply();
        assertEq(XanV1(proxy).implementation(), implV1, "proxy does not run V1");
        assertEq(XanV1(proxy).governanceCouncil(), _COUNCIL_MULTISIG, "V1 council mismatch");

        // 2. Deploy governance and prepare the V2 implementation (permissionless). The timelock deployed here is baked
        // into the V2 implementation bytecode as the token owner. `run` does not schedule — it returns `implV2`.
        (address implV2, address governor, address timelock,) =
            new PrepareXanV1Upgrade().run({proxy: proxy, councilMultisig: _COUNCIL_MULTISIG});

        // 3. The council Safe schedules the prepared implementation (the transaction the script surfaces via `implV2`).
        vm.prank(_COUNCIL_MULTISIG);
        XanV1(proxy).scheduleCouncilUpgrade({impl: implV2});

        (address scheduledImpl, uint48 endTime) = XanV1(proxy).scheduledCouncilUpgrade();
        assertEq(scheduledImpl, implV2, "council did not schedule the V2 implementation");
        assertEq(endTime, Time.timestamp() + Parameters.DELAY_DURATION, "unexpected upgrade delay");

        // 4. Wait out the council delay, then execute the (permissionless) upgrade.
        vm.warp(endTime);
        address executed = new UpgradeXanV1().run({proxy: proxy});
        assertEq(executed, implV2, "executed a different implementation than scheduled");

        // 5. The proxy now runs XanV2 with the state baked into the implementation bytecode by `PrepareXanV1Upgrade`:
        // the deployed timelock owns the token, the supply is conserved, and the vesting schedule matches the audited
        // `Parameters`.
        XanV2 tokenV2 = XanV2(proxy);
        assertEq(tokenV2.implementation(), implV2, "proxy not upgraded to V2");
        assertEq(tokenV2.owner(), timelock, "owner is not the deployed timelock");
        assertEq(tokenV2.totalSupply(), supplyBefore, "supply changed by the upgrade");
        assertEq(tokenV2.vestingStart(), Parameters.VESTING_START, "vesting start mismatch");
        assertEq(tokenV2.vestingEnd(), Parameters.VESTING_START + Parameters.VESTING_DURATION, "vesting end mismatch");

        // 6. Governance is now live on XanV2's timestamp clock. The quorum-numerator checkpoint recorded when the
        // governor was deployed (step 2) is timestamp-keyed, so `quorum(timepoint)` returns the configured fraction of
        // the voting supply seeded by the upgrade. `getPastTotalSupply` rejects the current timepoint, so advance one
        // second past the upgrade before querying.
        vm.warp(endTime + 1);
        uint256 expectedNumerator = Parameters.QUORUM_RATIO_NUMERATOR * 100 / Parameters.QUORUM_RATIO_DENOMINATOR;
        assertEq(
            XanGovernor(payable(governor)).quorum(endTime),
            supplyBefore * expectedNumerator / 100,
            "quorum is not the configured fraction of the seeded voting supply"
        );
    }
}
