// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {XAN_TOKEN, XAN_V2_VESTING_PROXY} from "../../script/DeployXanV2Vesting.s.sol";
import {GenerateXanV2VestingRecipientsPayload} from "../../script/GenerateXanV2VestingRecipientsPayload.s.sol";
import {IXanV2Vesting} from "../../src/interfaces/IXanV2Vesting.sol";
import {Parameters} from "../../src/libs/Parameters.sol";
import {XanV2Vesting} from "../../src/XanV2Vesting.sol";
import {XanV2VestingFixture} from "../fixtures/XanV2VestingFixture.sol";

contract GenerateXanV2VestingRecipientsPayloadTest is XanV2VestingFixture {
    string internal constant _RECIPIENTS_FIXTURE_PATH = "test/fixtures/xan-v2-vesting-recipients.json";

    GenerateXanV2VestingRecipientsPayload internal _script;

    function setUp() public override {
        super.setUp();
        _script = new GenerateXanV2VestingRecipientsPayload();
    }

    function test_run_writes_the_payload_that_is_in_the_payload_file() public {
        string memory payload = vm.readFile(_script.PAYLOAD_PATH());

        _script.run();

        assertEq(vm.readFile(_script.PAYLOAD_PATH()), payload, "run `just vesting-recipients-payload`");
    }

    function test_check_reverts_on_an_empty_list() public {
        vm.expectRevert(GenerateXanV2VestingRecipientsPayload.ZeroRecipientsNotAllowed.selector);
        _script.check({recipients: new IXanV2Vesting.Recipient[](0), totalPrincipal: 0});
    }

    function test_check_reverts_on_the_zero_account() public {
        vm.expectRevert(abi.encodeWithSelector(GenerateXanV2VestingRecipientsPayload.ZeroAccountNotAllowed.selector, 1));
        _script.check({recipients: _aliceAnd(address(0), _PRINCIPAL), totalPrincipal: 2 * _PRINCIPAL});
    }

    function test_check_reverts_on_the_proxy() public {
        vm.expectRevert(
            abi.encodeWithSelector(GenerateXanV2VestingRecipientsPayload.ProxyRecipientNotAllowed.selector, 1)
        );
        _script.check({recipients: _aliceAnd(XAN_V2_VESTING_PROXY, _PRINCIPAL), totalPrincipal: 2 * _PRINCIPAL});
    }

    function test_check_reverts_on_the_token() public {
        vm.expectRevert(
            abi.encodeWithSelector(GenerateXanV2VestingRecipientsPayload.TokenRecipientNotAllowed.selector, 1)
        );
        _script.check({recipients: _aliceAnd(XAN_TOKEN, _PRINCIPAL), totalPrincipal: 2 * _PRINCIPAL});
    }

    function test_check_reverts_on_a_zero_principal() public {
        vm.expectRevert(
            abi.encodeWithSelector(GenerateXanV2VestingRecipientsPayload.ZeroPrincipalNotAllowed.selector, 1)
        );
        _script.check({recipients: _aliceAnd(_BOB, 0), totalPrincipal: _PRINCIPAL});
    }

    function test_check_reverts_on_an_account_listed_twice() public {
        vm.expectRevert(
            abi.encodeWithSelector(GenerateXanV2VestingRecipientsPayload.RecipientListedTwice.selector, 1, _ALICE)
        );
        _script.check({recipients: _aliceAnd(_ALICE, _PRINCIPAL), totalPrincipal: 2 * _PRINCIPAL});
    }

    function test_check_reverts_if_the_principals_do_not_add_up_to_the_total_principal() public {
        uint256 sum = 2 * _PRINCIPAL;

        vm.expectRevert(
            abi.encodeWithSelector(GenerateXanV2VestingRecipientsPayload.TotalPrincipalMismatch.selector, sum - 1, sum)
        );
        _script.check({recipients: _aliceAnd(_BOB, _PRINCIPAL), totalPrincipal: sum - 1});
    }

    function test_payload_reports_the_recipient_count_and_the_total_principal() public {
        string memory payload =
            _script.payload({recipients: _aliceAnd(_BOB, _PRINCIPAL), totalPrincipal: 2 * _PRINCIPAL});

        assertEq(vm.parseJsonUint(payload, ".recipientCount"), 2);
        assertEq(vm.parseJsonUint(payload, ".totalPrincipal"), 2 * _PRINCIPAL);
    }

    function test_payload_adds_the_recipients_of_the_file_when_the_owner_submits_it() public {
        (IXanV2Vesting.Recipient[] memory recipients, uint256 totalPrincipal) =
            _script.readRecipients(_script.RECIPIENTS_PATH());
        string memory payload = _script.payload({recipients: recipients, totalPrincipal: totalPrincipal});
        address to = vm.parseJsonAddress(payload, ".to");
        uint256 value = vm.parseUint(vm.parseJsonString(payload, ".value"));
        bytes memory data = vm.parseJsonBytes(payload, ".data");

        XanV2Vesting vesting = _deployPinnedVesting();
        assertEq(to, address(vesting), "the payload must call the proxy of Ethereum mainnet and Sepolia");

        vm.prank(_OWNER);
        (bool success,) = to.call{value: value}(data);

        assertTrue(success);
        IXanV2Vesting.Recipient[] memory added = vesting.getRecipients();
        assertEq(added.length, recipients.length);
        for (uint256 i = 0; i < recipients.length; ++i) {
            assertEq(added[i].account, recipients[i].account);
            assertEq(added[i].principal, recipients[i].principal);
        }
        assertEq(vesting.totalPrincipal(), totalPrincipal);
    }

    function test_readRecipients_reads_the_exact_principals_and_the_total_principal_of_a_file() public view {
        (IXanV2Vesting.Recipient[] memory recipients, uint256 totalPrincipal) =
            _script.readRecipients(_RECIPIENTS_FIXTURE_PATH);

        assertEq(recipients.length, 2);
        assertEq(recipients[0].account, 0x1111111111111111111111111111111111111111);
        assertEq(recipients[0].principal, 123_456_789_123_456_789_123_456_789);
        assertEq(recipients[1].account, 0x2222222222222222222222222222222222222222);
        assertEq(recipients[1].principal, 1e18);
        assertEq(totalPrincipal, recipients[0].principal + recipients[1].principal);
    }

    function test_check_accepts_the_recipients_file() public view {
        (IXanV2Vesting.Recipient[] memory recipients, uint256 totalPrincipal) =
            _script.readRecipients(_script.RECIPIENTS_PATH());

        _script.check({recipients: recipients, totalPrincipal: totalPrincipal});
    }

    function test_instruction_names_the_council_multisig() public view {
        assertTrue(vm.contains(_script.instruction(), vm.toString(Parameters.COUNCIL_MULTISIG)));
    }

    /// @dev Lists Alice with `_PRINCIPAL` first, so that the entry under test is at index 1.
    function _aliceAnd(address account, uint256 principal)
        internal
        view
        returns (IXanV2Vesting.Recipient[] memory recipients)
    {
        recipients = new IXanV2Vesting.Recipient[](2);
        recipients[0] = IXanV2Vesting.Recipient({account: _ALICE, principal: _PRINCIPAL});
        recipients[1] = IXanV2Vesting.Recipient({account: account, principal: principal});
    }

    /// @dev Starts the proxies without recipients, so that a payload adds every recipient of the vesting contract.
    function _initialRecipients() internal pure override returns (IXanV2Vesting.Recipient[] memory recipients) {
        recipients = new IXanV2Vesting.Recipient[](0);
    }
}
