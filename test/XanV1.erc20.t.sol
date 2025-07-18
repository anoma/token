// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {Upgrades, UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Test} from "forge-std/Test.sol";

import {MockXanV1, XanV1} from "./mocks/XanV1.m.sol";

contract MockXanV1ERC20Test is Test {
    using UnsafeUpgrades for address;

    address internal constant _COUNCIL = address(uint160(1));

    address internal _alice;
    address internal _bob;
    MockXanV1 internal _xanProxyMock;

    function setUp() public {
        (, _alice,) = vm.readCallers();

        // Deploy proxy and mint tokens for the `_tokenHolder`.
        vm.prank(_alice);
        _xanProxyMock = MockXanV1(
            Upgrades.deployUUPSProxy({
                contractName: "XanV1.m.sol:MockXanV1",
                initializerData: abi.encodeCall(XanV1.initializeV1, (_alice, _COUNCIL))
            })
        );

        _bob = vm.randomAddress();
    }

    function test_update_MINT_does_not_require_address_0_to_hold_unlocked_tokens() public {
        address from = address(0);
        address to = _bob;
        uint256 value = 100;

        assertEq(_xanProxyMock.balanceOf(from), 0);
        assertEq(_xanProxyMock.unlockedBalanceOf(from), 0);
        uint256 toBalanceBeforeUpdate = _xanProxyMock.unlockedBalanceOf(to);

        _xanProxyMock.update({from: from, to: to, value: value});

        assertEq(_xanProxyMock.balanceOf(from), 0);
        assertEq(_xanProxyMock.unlockedBalanceOf(from), 0);
        assertEq(_xanProxyMock.balanceOf(to), toBalanceBeforeUpdate + value);
    }

    function test_update_TRANSFER_reverts_transfer_if_the_from_address_has_insufficient_unlocked_tokens() public {
        address from = _bob;
        address to = _alice;
        uint256 value = 100;

        assertEq(_xanProxyMock.balanceOf(from), 0);
        assertEq(_xanProxyMock.unlockedBalanceOf(from), 0);

        vm.expectRevert(
            abi.encodeWithSelector(XanV1.UnlockedBalanceInsufficient.selector, from, 0, value), address(_xanProxyMock)
        );
        _xanProxyMock.update({from: from, to: to, value: value});
    }

    function test_update_TRANSFER_updates_if_the_from_address_has_sufficient_unlocked_tokens() public {
        address from = _alice;
        address to = _bob;
        uint256 value = 100;

        uint256 fromBalanceBeforeUpdate = _xanProxyMock.unlockedBalanceOf(from);
        uint256 toBalanceBeforeUpdate = _xanProxyMock.unlockedBalanceOf(to);

        _xanProxyMock.update({from: from, to: to, value: value});

        assertEq(_xanProxyMock.balanceOf(from), fromBalanceBeforeUpdate - value);
        assertEq(_xanProxyMock.balanceOf(to), toBalanceBeforeUpdate + value);
    }

    function test_update_BURN_reverts_if_the_from_address_has_unsufficient_unlocked_tokens() public {
        address from = _bob;
        address to = address(0);
        uint256 value = 100;

        vm.expectRevert(
            abi.encodeWithSelector(XanV1.UnlockedBalanceInsufficient.selector, from, 0, value), address(_xanProxyMock)
        );
        _xanProxyMock.update({from: from, to: to, value: value});
    }

    function test_update_BURN_updates_if_the_from_address_has_sufficient_unlocked_tokens() public {
        address from = _alice;
        address to = address(0);
        uint256 value = 100;

        uint256 fromBalanceBeforeUpdate = _xanProxyMock.unlockedBalanceOf(from);
        assertEq(_xanProxyMock.unlockedBalanceOf(to), 0);

        _xanProxyMock.update({from: from, to: to, value: value});

        assertEq(_xanProxyMock.balanceOf(from), fromBalanceBeforeUpdate - value);
        assertEq(_xanProxyMock.balanceOf(to), 0);
    }
}
