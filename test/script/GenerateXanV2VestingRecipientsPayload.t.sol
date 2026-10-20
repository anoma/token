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

    function test_run_writes_the_batch_files_that_are_in_safe_payloads() public {
        string memory mainnet = vm.readFile(_script.MAINNET_PAYLOAD_PATH());
        string memory sepolia = vm.readFile(_script.SEPOLIA_PAYLOAD_PATH());

        _script.run();

        assertEq(vm.readFile(_script.MAINNET_PAYLOAD_PATH()), mainnet, "run `just vesting-recipients-payload`");
        assertEq(vm.readFile(_script.SEPOLIA_PAYLOAD_PATH()), sepolia, "run `just vesting-recipients-payload`");
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

    function test_batchFile_adds_the_recipients_when_the_owner_submits_its_transaction() public {
        (IXanV2Vesting.Recipient[] memory recipients, uint256 totalPrincipal) =
            _script.readRecipients(_RECIPIENTS_FIXTURE_PATH);
        string memory json = _script.batchFile({
            chainId: _script.MAINNET_CHAIN_ID(), recipients: recipients, totalPrincipal: totalPrincipal
        });
        address to = vm.parseJsonAddress(json, ".transactions[0].to");
        uint256 value = vm.parseUint(vm.parseJsonString(json, ".transactions[0].value"));
        bytes memory data = vm.parseJsonBytes(json, ".transactions[0].data");

        XanV2Vesting vesting = _deployPinnedVesting();
        assertEq(to, address(vesting), "the batch must call the proxy of Ethereum mainnet and Sepolia");

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

    function test_batchFile_has_the_checksum_that_the_transaction_builder_computes() public view {
        (IXanV2Vesting.Recipient[] memory recipients, uint256 totalPrincipal) =
            _script.readRecipients(_RECIPIENTS_FIXTURE_PATH);
        string memory mainnet = _script.batchFile({
            chainId: _script.MAINNET_CHAIN_ID(), recipients: recipients, totalPrincipal: totalPrincipal
        });
        string memory sepolia = _script.batchFile({
            chainId: _script.SEPOLIA_CHAIN_ID(), recipients: recipients, totalPrincipal: totalPrincipal
        });

        // The checksums that `apps/tx-builder/src/lib/checksum.ts` of the Safe Transaction Builder computes.
        assertEq(
            vm.parseJsonString(mainnet, ".meta.checksum"),
            "0xe571a69d8f4879e92ae3a428c642be8cfd23b3c8ca69f82c14e74782912f51fd"
        );
        assertEq(
            vm.parseJsonString(sepolia, ".meta.checksum"),
            "0x33eea47f5144722945ba2471849dcde3450843fc0a23ef71eefe38d1dec6bcc0"
        );
    }

    function test_batchFile_names_the_chain_and_the_council_multisig() public view {
        IXanV2Vesting.Recipient[] memory recipients = new IXanV2Vesting.Recipient[](0);
        string memory mainnet =
            _script.batchFile({chainId: _script.MAINNET_CHAIN_ID(), recipients: recipients, totalPrincipal: 0});
        string memory sepolia =
            _script.batchFile({chainId: _script.SEPOLIA_CHAIN_ID(), recipients: recipients, totalPrincipal: 0});

        assertEq(vm.parseJsonString(mainnet, ".chainId"), "1");
        assertEq(vm.parseJsonString(sepolia, ".chainId"), "11155111");
        assertEq(vm.parseJsonAddress(mainnet, ".meta.createdFromSafeAddress"), Parameters.COUNCIL_MULTISIG);
        assertEq(vm.parseJsonAddress(sepolia, ".meta.createdFromSafeAddress"), Parameters.COUNCIL_MULTISIG);
    }

    function test_batchFile_describes_the_recipient_count_and_the_total_principal() public view {
        string memory json = _script.batchFile({
            chainId: _script.MAINNET_CHAIN_ID(), recipients: _aliceAnd(_BOB, _PRINCIPAL), totalPrincipal: 2 * _PRINCIPAL
        });
        string memory description = vm.parseJsonString(json, ".meta.description");

        assertTrue(vm.contains(description, "Recipient count: 2."));
        assertTrue(vm.contains(description, string.concat("Total principal: ", vm.toString(2 * _PRINCIPAL), " ")));
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

    /// @dev Starts the proxies without recipients, so that a batch adds every recipient of the vesting contract.
    function _initialRecipients() internal pure override returns (IXanV2Vesting.Recipient[] memory recipients) {
        recipients = new IXanV2Vesting.Recipient[](0);
    }
}
