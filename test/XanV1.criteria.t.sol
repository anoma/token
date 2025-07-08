// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";

import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {Upgrades, UnsafeUpgrades, Options} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Test} from "forge-std/Test.sol";

import {Parameters} from "../src/libs/Parameters.sol";
import {MockXanV1, XanV1} from "./mocks/XanV1.m.sol";

contract MockXanV1CriteriaTest is Test {
    using UnsafeUpgrades for address;
    using ERC1967Utils for address;
    using SafeERC20 for MockXanV1;

    address internal constant _COUNCIL = address(uint160(1));
    address internal constant _IMPL_A = address(uint160(2));
    address internal constant _IMPL_B = address(uint160(3));

    address internal _defaultSender;
    address internal _alice;
    address internal _bob;

    MockXanV1 internal _xanProxyMock;

    function setUp() public {
        (, _defaultSender,) = vm.readCallers();

        // Deploy proxy and mint tokens for the `_defaultSender`.
        vm.prank(_defaultSender);
        _xanProxyMock = MockXanV1(
            Upgrades.deployUUPSProxy({
                contractName: "XanV1.m.sol:MockXanV1",
                initializerData: abi.encodeCall(XanV1.initializeV1, (_defaultSender, _COUNCIL))
            })
        );

        _alice = vm.randomAddress();
        _bob = vm.randomAddress();
    }

    function test_isQuorumAndMinLockedSupplyReached_returns_false_if_the_quorum_threshold_is_not_exceeded() public {
        uint256 halfOfSupply = _xanProxyMock.totalSupply() / 2;

        vm.startPrank(_defaultSender);
        _xanProxyMock.safeTransfer(_alice, halfOfSupply);
        _xanProxyMock.safeTransfer(_bob, halfOfSupply);
        vm.stopPrank();

        assertEq(_xanProxyMock.balanceOf(_defaultSender), 0);
        assertEq(_xanProxyMock.balanceOf(_alice), halfOfSupply);
        assertEq(_xanProxyMock.balanceOf(_bob), halfOfSupply);

        vm.startPrank(_alice);
        _xanProxyMock.lock(halfOfSupply);
        _xanProxyMock.castVote(_IMPL_A);
        vm.stopPrank();

        vm.prank(_bob);
        _xanProxyMock.lock(halfOfSupply);
        vm.stopPrank();

        assertEq(_xanProxyMock.isQuorumAndMinLockedSupplyReached(_IMPL_A), false);
    }

    function test_isQuorumAndMinLockedSupplyReached_returns_true_if_the_quorum_threshold_is_exceeded_by_one_vote()
        public
    {
        uint256 halfOfSupply = _xanProxyMock.totalSupply() / 2;

        vm.startPrank(_defaultSender);
        _xanProxyMock.safeTransfer(_alice, halfOfSupply + 1);
        _xanProxyMock.safeTransfer(_bob, halfOfSupply - 1);
        vm.stopPrank();

        assertEq(_xanProxyMock.balanceOf(_defaultSender), 0);
        assertEq(_xanProxyMock.balanceOf(_alice), halfOfSupply + 1);
        assertEq(_xanProxyMock.balanceOf(_bob), halfOfSupply - 1);

        vm.startPrank(_alice);
        _xanProxyMock.lock(halfOfSupply + 1);
        _xanProxyMock.castVote(_IMPL_A);
        vm.stopPrank();

        vm.startPrank(_bob);
        _xanProxyMock.lock(halfOfSupply - 1);
        vm.stopPrank();
        assertEq(_xanProxyMock.lockedSupply(), _xanProxyMock.totalSupply());

        assertEq(_xanProxyMock.isQuorumAndMinLockedSupplyReached(_IMPL_A), true);
    }

    function test_authorizeUpgrade_requires_the_threshold_to_be_passed_with_one_more_vote_than_the_limit() public {
        revert("TODO");
    }
}
