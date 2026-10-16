// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Test} from "forge-std/Test.sol";

import {DeployXanV2Vesting, XAN_TOKEN, XAN_V2_VESTING_PROXY} from "../../script/DeployXanV2Vesting.s.sol";
import {Parameters} from "../../src/libs/Parameters.sol";
import {XanV2} from "../../src/XanV2.sol";
import {XanV2Vesting} from "../../src/XanV2Vesting.sol";

contract DeployXanV2VestingTest is Test {
    /// @dev The deployer of the governance stack and its nonce on Ethereum mainnet and Sepolia.
    address internal constant _DEPLOYER = 0xc461247a7375cF7c70a576d636aA3dd38ff3bb2f;
    uint64 internal constant _DEPLOYER_NONCE = 11;

    address internal constant _IMPLEMENTATION = 0xA4b1B4032c30Ba42a44c3616D3AB95d10170De55;

    DeployXanV2Vesting internal _script;

    function setUp() public {
        _script = new DeployXanV2Vesting();

        // The constructor of the implementation reads only the schedule of the pinned token, so the code of a `XanV2`
        // implementation with the production schedule stands in for the proxy.
        XanV2 token = new XanV2(makeAddr("owner"), Parameters.XAN_VESTING_START, Parameters.XAN_VESTING_DURATION);
        vm.etch(XAN_TOKEN, address(token).code);

        vm.setNonce(_DEPLOYER, _DEPLOYER_NONCE);
    }

    function test_deploy_deploys_at_the_pinned_addresses_with_the_schedule_and_the_owner() public {
        (address proxy, address implementation) = _script.deploy({deployer: _DEPLOYER});
        XanV2Vesting vesting = XanV2Vesting(proxy);

        assertEq(proxy, XAN_V2_VESTING_PROXY);
        assertEq(implementation, _IMPLEMENTATION);
        assertEq(UnsafeUpgrades.getImplementationAddress(proxy), implementation);
        assertEq(address(vesting.XAN_TOKEN()), XAN_TOKEN);
        assertEq(vesting.vestingStart(), Parameters.XAN_VESTING_START);
        assertEq(vesting.vestingEnd(), Parameters.XAN_VESTING_START + Parameters.XAN_VESTING_DURATION);
        assertEq(vesting.owner(), Parameters.COUNCIL_MULTISIG);
    }

    function test_deploy_reverts_if_the_proxy_would_land_at_another_address() public {
        vm.setNonce(_DEPLOYER, _DEPLOYER_NONCE + 1);
        address predictedProxy = vm.computeCreateAddress(_DEPLOYER, _DEPLOYER_NONCE + 2);

        vm.expectRevert(
            abi.encodeWithSelector(
                DeployXanV2Vesting.UnexpectedProxyAddress.selector, XAN_V2_VESTING_PROXY, predictedProxy
            )
        );
        _script.deploy({deployer: _DEPLOYER});
    }

    function test_run_reverts_unless_the_sender_is_the_deployer_at_its_nonce() public {
        vm.expectPartialRevert(DeployXanV2Vesting.UnexpectedProxyAddress.selector);
        _script.run();
    }
}
