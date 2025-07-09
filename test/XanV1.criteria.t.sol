// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Upgrades, UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Test} from "forge-std/Test.sol";

import {Parameters} from "../src/libs/Parameters.sol";
import {MockXanV1, XanV1} from "./mocks/XanV1.m.sol";

contract MockXanV1CriteriaTest is Test {
    using UnsafeUpgrades for address;
    using SafeERC20 for MockXanV1;

    address internal constant _COUNCIL = address(uint160(1));
    address internal constant _NEW_IMPL = address(uint160(2));

    address internal _tokenHolder;
    MockXanV1 internal _xanProxyMock;

    function setUp() public {
        (, _tokenHolder,) = vm.readCallers();

        // Deploy proxy and mint tokens for the `_tokenHolder`.
        vm.prank(_tokenHolder);
        _xanProxyMock = MockXanV1(
            Upgrades.deployUUPSProxy({
                contractName: "XanV1.m.sol:MockXanV1",
                initializerData: abi.encodeCall(XanV1.initializeV1, (_tokenHolder, _COUNCIL))
            })
        );
    }

    function test_isQuorumAndMinLockedSupplyReached_returns_false_if_the_quorum_threshold_is_not_exceeded() public {
        vm.startPrank(_tokenHolder);
        _xanProxyMock.lock(Parameters.MIN_LOCKED_SUPPLY / 2);
        _xanProxyMock.castVote(_NEW_IMPL);

        uint256 votum = _xanProxyMock.votum(_tokenHolder, _NEW_IMPL);
        _xanProxyMock.lock(Parameters.MIN_LOCKED_SUPPLY - votum);

        assertEq(_xanProxyMock.lockedSupply(), Parameters.MIN_LOCKED_SUPPLY);
        assertEq(_xanProxyMock.isQuorumAndMinLockedSupplyReached(_NEW_IMPL), false);
    }

    function test_isQuorumAndMinLockedSupplyReached_returns_true_if_the_quorum_threshold_is_exceeded_by_one_vote()
        public
    {
        vm.startPrank(_tokenHolder);
        _xanProxyMock.lock(Parameters.MIN_LOCKED_SUPPLY / 2 + 1);
        _xanProxyMock.castVote(_NEW_IMPL);

        uint256 votum = _xanProxyMock.votum(_tokenHolder, _NEW_IMPL);
        _xanProxyMock.lock(Parameters.MIN_LOCKED_SUPPLY - votum);

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
}
