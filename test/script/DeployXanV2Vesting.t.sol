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

    function test_run_reverts_on_mainnet_and_sepolia_if_the_proxy_would_land_at_another_address() public {
        uint256[2] memory chainIds = [uint256(1), 11_155_111];
        for (uint256 i = 0; i < chainIds.length; ++i) {
            vm.chainId(chainIds[i]);

            vm.expectPartialRevert(DeployXanV2Vesting.UnexpectedProxyAddress.selector);
            _script.run({xanToken: address(_xanV2Proxy), recipientsPath: _RECIPIENTS_PATH});
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
