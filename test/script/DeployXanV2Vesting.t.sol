// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";

import {DeployXanV2Vesting} from "../../script/DeployXanV2Vesting.s.sol";
import {IXanV2Vesting} from "../../src/interfaces/IXanV2Vesting.sol";
import {Parameters} from "../../src/libs/Parameters.sol";
import {XanV2Vesting} from "../../src/XanV2Vesting.sol";
import {XanV2Fixture} from "../fixtures/XanV2Fixture.sol";

contract DeployXanV2VestingTest is XanV2Fixture {
    string internal constant _RECIPIENTS_PATH = "test/fixtures/xan-v2-vesting-recipients.json";

    DeployXanV2Vesting internal _script;

    function setUp() public override {
        super.setUp();
        _script = new DeployXanV2Vesting();
    }

    function test_run_deploys_with_the_schedule_of_the_token_and_the_recipients_of_the_file() public {
        (address proxy, address implementation) =
            _script.run({xanToken: address(_xanV2Proxy), recipientsPath: _RECIPIENTS_PATH});
        XanV2Vesting vesting = XanV2Vesting(proxy);

        assertEq(UnsafeUpgrades.getImplementationAddress(proxy), implementation);
        assertEq(vesting.vestingStart(), _xanV2Proxy.vestingStart());
        assertEq(vesting.vestingEnd(), _xanV2Proxy.vestingEnd());
        assertEq(vesting.owner(), Parameters.COUNCIL_MULTISIG);

        IXanV2Vesting.Recipient[] memory recipients = _script.readRecipients(_RECIPIENTS_PATH);
        IXanV2Vesting.Recipient[] memory added = vesting.getRecipients();
        assertEq(added.length, recipients.length);
        for (uint256 i = 0; i < recipients.length; ++i) {
            assertEq(added[i].account, recipients[i].account);
            assertEq(added[i].principal, recipients[i].principal);
        }
    }

    function test_readRecipients_reads_the_accounts_and_the_exact_principals_of_the_file() public view {
        IXanV2Vesting.Recipient[] memory recipients = _script.readRecipients(_RECIPIENTS_PATH);

        assertEq(recipients.length, 2);
        assertEq(recipients[0].account, 0x1111111111111111111111111111111111111111);
        assertEq(recipients[0].principal, 123_456_789_123_456_789_123_456_789);
        assertEq(recipients[1].account, 0x2222222222222222222222222222222222222222);
        assertEq(recipients[1].principal, 1e18);
    }
}
