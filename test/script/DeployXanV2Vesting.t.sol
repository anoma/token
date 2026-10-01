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

    /// @dev The deployer of the governance stack and its nonce on Ethereum mainnet and Sepolia.
    address internal constant _DEPLOYER = 0xc461247a7375cF7c70a576d636aA3dd38ff3bb2f;
    uint64 internal constant _DEPLOYER_NONCE = 11;

    DeployXanV2Vesting internal _script;

    function setUp() public override {
        super.setUp();
        _script = new DeployXanV2Vesting();

        // The script deploys for the XAN token proxy of Ethereum mainnet and Sepolia, whose schedule the constructor of
        // the implementation reads. The code of the local V2 implementation returns the schedule of the local token.
        vm.etch(_script.XAN_TOKEN(), _xanV2Impl.code);
    }

    function test_run_reverts_while_the_recipient_file_is_empty() public {
        vm.skip(_script.readRecipients(_script.RECIPIENTS_PATH()).length != 0, "The recipient file lists recipients.");

        vm.expectRevert(DeployXanV2Vesting.ZeroRecipientsNotAllowed.selector);
        _script.run();
    }

    function test_run_deploys_the_recipients_of_the_file() public {
        IXanV2Vesting.Recipient[] memory recipients = _script.readRecipients(_script.RECIPIENTS_PATH());
        vm.skip(recipients.length == 0, "The recipient file is still empty.");

        (address proxy,) = _script.run();

        assertEq(XanV2Vesting(proxy).getRecipients().length, recipients.length);
    }

    function test_deploy_deploys_with_the_schedule_of_the_token_and_the_recipients() public {
        IXanV2Vesting.Recipient[] memory recipients = _script.readRecipients(_RECIPIENTS_PATH);

        (address proxy, address implementation) = _script.deploy(recipients);
        XanV2Vesting vesting = XanV2Vesting(proxy);

        assertEq(UnsafeUpgrades.getImplementationAddress(proxy), implementation);
        assertEq(address(vesting.XAN_TOKEN()), _script.XAN_TOKEN());
        assertEq(vesting.vestingStart(), _xanV2Proxy.vestingStart());
        assertEq(vesting.vestingEnd(), _xanV2Proxy.vestingEnd());
        assertEq(vesting.owner(), Parameters.COUNCIL_MULTISIG);

        IXanV2Vesting.Recipient[] memory added = vesting.getRecipients();
        assertEq(added.length, recipients.length);
        for (uint256 i = 0; i < recipients.length; ++i) {
            assertEq(added[i].account, recipients[i].account);
            assertEq(added[i].principal, recipients[i].principal);
        }
    }

    function test_deploy_reverts_on_an_empty_recipient_list() public {
        vm.expectRevert(DeployXanV2Vesting.ZeroRecipientsNotAllowed.selector);
        _script.deploy(new IXanV2Vesting.Recipient[](0));
    }

    function test_deploy_reverts_on_mainnet_and_sepolia_if_the_proxy_would_land_at_another_address() public {
        IXanV2Vesting.Recipient[] memory recipients = _script.readRecipients(_RECIPIENTS_PATH);

        uint256[2] memory chainIds = [uint256(1), 11_155_111];
        for (uint256 i = 0; i < chainIds.length; ++i) {
            vm.chainId(chainIds[i]);

            vm.expectPartialRevert(DeployXanV2Vesting.UnexpectedProxyAddress.selector);
            _script.deploy(recipients);
        }
    }

    function test_requireExpectedProxy_reverts_if_the_deployer_is_at_another_nonce() public {
        vm.setNonce(_DEPLOYER, _DEPLOYER_NONCE + 1);
        address predictedProxy = vm.computeCreateAddress(_DEPLOYER, _DEPLOYER_NONCE + 2);

        vm.expectRevert(
            abi.encodeWithSelector(
                DeployXanV2Vesting.UnexpectedProxyAddress.selector, _script.EXPECTED_PROXY(), predictedProxy
            )
        );
        _script.requireExpectedProxy(_DEPLOYER);
    }

    function test_requireExpectedProxy_passes_for_the_deployer_at_its_nonce() public {
        vm.setNonce(_DEPLOYER, _DEPLOYER_NONCE);

        _script.requireExpectedProxy(_DEPLOYER);
    }

    function test_EXPECTED_PROXY_is_the_address_of_the_deployer_at_the_nonce_after_the_implementation() public view {
        assertEq(_script.EXPECTED_PROXY(), vm.computeCreateAddress(_DEPLOYER, _DEPLOYER_NONCE + 1));
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
