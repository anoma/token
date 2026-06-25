// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Upgrades, UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Test} from "forge-std/Test.sol";

import {Parameters} from "../src/libs/Parameters.sol";
import {MockXanV1, XanV1} from "./mocks/MockXanV1.sol";

contract MockXanV1CriteriaTest is Test {
    using UnsafeUpgrades for address;
    using SafeERC20 for MockXanV1;

    address internal immutable _COUNCIL = makeAddr("council");
    address internal immutable _NEW_IMPL = makeAddr("newImpl");

    address internal _tokenHolder;
    MockXanV1 internal _xanProxyMock;

    function setUp() public {
        (, _tokenHolder,) = vm.readCallers();

        // Deploy proxy and mint tokens for the `_tokenHolder`.
        vm.prank(_tokenHolder);
        _xanProxyMock = MockXanV1(
            Upgrades.deployUUPSProxy({
                contractName: "MockXanV1.sol:MockXanV1",
                initializerData: abi.encodeCall(XanV1.initializeV1, (_tokenHolder, _COUNCIL))
            })
        );
    }

    function test_isQuorumAndMinLockedSupplyReached_returns_false_if_the_quorum_threshold_is_not_exceeded() public {
        vm.startPrank(_tokenHolder);
        _xanProxyMock.lock(Parameters.MIN_LOCKED_SUPPLY / 2);
        _xanProxyMock.castVote(_NEW_IMPL);

        uint256 votes = _xanProxyMock.getVotes(_tokenHolder, _NEW_IMPL);
        _xanProxyMock.lock(Parameters.MIN_LOCKED_SUPPLY - votes);

        assertEq(_xanProxyMock.lockedSupply(), Parameters.MIN_LOCKED_SUPPLY);
        assertEq(_xanProxyMock.isQuorumAndMinLockedSupplyReached(_NEW_IMPL), false);
    }

    function test_isQuorumAndMinLockedSupplyReached_returns_true_if_the_quorum_threshold_is_exceeded_by_one_vote()
        public
    {
        vm.startPrank(_tokenHolder);
        _xanProxyMock.lock(Parameters.MIN_LOCKED_SUPPLY / 2 + 1);
        _xanProxyMock.castVote(_NEW_IMPL);

        uint256 votes = _xanProxyMock.getVotes(_tokenHolder, _NEW_IMPL);
        _xanProxyMock.lock(Parameters.MIN_LOCKED_SUPPLY - votes);

        assertEq(_xanProxyMock.lockedSupply(), Parameters.MIN_LOCKED_SUPPLY);
        assertEq(_xanProxyMock.isQuorumAndMinLockedSupplyReached(_NEW_IMPL), true);
    }

    function test_isQuorumAndMinLockedSupplyReached_returns_false_if_the_min_locked_supply_is_not_met_by_one_vote()
        public
    {
        vm.startPrank(_tokenHolder);
        _xanProxyMock.lock(Parameters.MIN_LOCKED_SUPPLY - 1);
        _xanProxyMock.castVote(_NEW_IMPL);

        assertLt(_xanProxyMock.lockedSupply(), Parameters.MIN_LOCKED_SUPPLY);
        assertEq(_xanProxyMock.isQuorumAndMinLockedSupplyReached(_NEW_IMPL), false);
    }

    function test_isQuorumAndMinLockedSupplyReached_returns_true_if_the_min_locked_supply_is_exactly_met() public {
        vm.startPrank(_tokenHolder);
        _xanProxyMock.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxyMock.castVote(_NEW_IMPL);

        assertEq(_xanProxyMock.lockedSupply(), Parameters.MIN_LOCKED_SUPPLY);
        assertEq(_xanProxyMock.isQuorumAndMinLockedSupplyReached(_NEW_IMPL), true);
    }

    function test_checkDelayCriterion_reverts_if_the_delay_period_has_not_started() public {
        // `endTime == 0` means no upgrade is scheduled: a defense-in-depth guard that the scheduling flow, which
        // always sets a non-zero end time alongside the implementation, never reaches.
        vm.expectRevert(abi.encodeWithSelector(XanV1.DelayPeriodNotStarted.selector, uint48(0)));
        _xanProxyMock.checkDelayCriterion(0);
    }
}
