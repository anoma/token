// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {DeployXanVesting} from "../../script/DeployXanVesting.s.sol";
import {IXanVesting} from "../../src/interfaces/IXanVesting.sol";
import {XanVesting} from "../../src/XanVesting.sol";
import {XanV2Fixture} from "../fixtures/XanV2Fixture.sol";

contract DeployXanVestingTest is XanV2Fixture {
    string internal constant _RECIPIENTS_PATH = "test/fixtures/xan-vesting-recipients.json";

    address internal immutable _OWNER = makeAddr("owner");

    DeployXanVesting internal _script;

    function setUp() public override {
        super.setUp();
        _script = new DeployXanVesting();
    }

    function test_run_deploys_with_the_schedule_of_the_token_and_the_recipients_of_the_file() public {
        XanVesting vesting = XanVesting(
            _script.run({xanToken: address(_xanV2Proxy), initialOwner: _OWNER, recipientsPath: _RECIPIENTS_PATH})
        );

        assertEq(vesting.vestingStart(), _xanV2Proxy.vestingStart());
        assertEq(vesting.vestingEnd(), _xanV2Proxy.vestingEnd());
        assertEq(vesting.owner(), _OWNER);

        IXanVesting.Recipient[] memory recipients = _script.readRecipients(_RECIPIENTS_PATH);
        IXanVesting.Recipient[] memory added = vesting.getRecipients();
        assertEq(added.length, recipients.length);
        for (uint256 i = 0; i < recipients.length; ++i) {
            assertEq(added[i].account, recipients[i].account);
            assertEq(added[i].principal, recipients[i].principal);
        }
    }

    function test_readRecipients_reads_the_accounts_and_the_exact_principals_of_the_file() public view {
        IXanVesting.Recipient[] memory recipients = _script.readRecipients(_RECIPIENTS_PATH);

        assertEq(recipients.length, 2);
        assertEq(recipients[0].account, 0x1111111111111111111111111111111111111111);
        assertEq(recipients[0].principal, 123_456_789_123_456_789_123_456_789);
        assertEq(recipients[1].account, 0x2222222222222222222222222222222222222222);
        assertEq(recipients[1].principal, 1e18);
    }
}
