// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {Upgrades, UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";

import {Test} from "forge-std/Test.sol";

import {Parameters} from "../src/libs/Parameters.sol";
import {IXanV1, XanV1} from "../src/XanV1.sol";

contract XanV1UnitTest is Test {
    address internal constant _NEW_IMPL = address(uint160(1));
    address internal constant _OTHER_NEW_IMPL = address(uint160(2));
    address internal constant _RECEIVER = address(uint160(3));
    address internal constant _COUNCIL = address(uint160(4));

    address internal _defaultSender;
    XanV1 internal _xanProxy;

    function setUp() public {
        (, _defaultSender,) = vm.readCallers();

        _xanProxy = XanV1(
            Upgrades.deployUUPSProxy({
                contractName: "XanV1.sol:XanV1",
                initializerData: abi.encodeCall(XanV1.initializeV1, (_defaultSender, _COUNCIL))
            })
        );
    }

    function test_authorizeUpgrade_reverts_for_an_upgrade_to_address_0() public {
        vm.expectRevert(abi.encodeWithSelector(XanV1.ImplementationZero.selector), address(_xanProxy));
        _xanProxy.upgradeToAndCall({newImplementation: address(0), data: ""});
    }

    function test_authorizeUpgrade_reverts_if_implementation_has_not_been_voted_on() public {
        vm.expectRevert(abi.encodeWithSelector(XanV1.DelayPeriodNotStarted.selector), address(_xanProxy));
        _xanProxy.upgradeToAndCall({newImplementation: _NEW_IMPL, data: ""});
    }

    function test_authorizeUpgrade_reverts_if_the_delay_period_has_passed_for_a_different_implementation() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_OTHER_NEW_IMPL);
        vm.stopPrank();

        _xanProxy.startVoterBodyUpgradeDelay(_OTHER_NEW_IMPL);
        skip(Parameters.DELAY_DURATION);

        vm.expectRevert(
            abi.encodeWithSelector(XanV1.ImplementationNotDelayed.selector, _OTHER_NEW_IMPL, _NEW_IMPL),
            address(_xanProxy)
        );
        _xanProxy.upgradeToAndCall({newImplementation: _NEW_IMPL, data: ""});
    }

    function test_authorizeUpgrade_reverts_if_delay_period_has_not_started() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(_xanProxy.calculateQuorumThreshold() + 1);
        _xanProxy.castVote(_NEW_IMPL);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(XanV1.DelayPeriodNotStarted.selector), address(_xanProxy));
        _xanProxy.upgradeToAndCall({newImplementation: _NEW_IMPL, data: ""});
    }

    function test_authorizeUpgrade_reverts_if_delay_period_has_not_ended() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_NEW_IMPL);
        vm.stopPrank();

        _xanProxy.startVoterBodyUpgradeDelay(_NEW_IMPL);

        vm.expectRevert(abi.encodeWithSelector(XanV1.DelayPeriodNotEnded.selector), address(_xanProxy));
        _xanProxy.upgradeToAndCall({newImplementation: _NEW_IMPL, data: ""});
    }

    function test_authorizeUpgrade_reverts_if_quorum_is_not_met() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_NEW_IMPL);
        vm.stopPrank();

        _xanProxy.startVoterBodyUpgradeDelay(_NEW_IMPL);
        skip(Parameters.DELAY_DURATION);

        vm.prank(_defaultSender);
        _xanProxy.revokeVote(_NEW_IMPL);

        vm.expectRevert(abi.encodeWithSelector(XanV1.QuorumNotReached.selector, _NEW_IMPL), address(_xanProxy));
        _xanProxy.upgradeToAndCall({newImplementation: _NEW_IMPL, data: ""});
    }

    function test_authorizeUpgrade_reverts_if_implementation_is_not_best_ranked() public {
        vm.startPrank(_defaultSender);

        uint256 quorumThreshold =
            (_xanProxy.totalSupply() * Parameters.QUORUM_RATIO_NUMERATOR) / Parameters.QUORUM_RATIO_DENOMINATOR;

        // Meet the quorum threshold with one excess vote.
        _xanProxy.lock(quorumThreshold + 1);
        _xanProxy.castVote(_NEW_IMPL);
        assertEq(_xanProxy.proposedImplementationByRank(0), _NEW_IMPL);

        _xanProxy.startVoterBodyUpgradeDelay(_NEW_IMPL);
        _xanProxy.lock(1);
        _xanProxy.castVote(_OTHER_NEW_IMPL);
        vm.stopPrank();

        assertEq(_xanProxy.proposedImplementationByRank(0), _OTHER_NEW_IMPL); // Delay has not started
        assertEq(_xanProxy.proposedImplementationByRank(1), _NEW_IMPL); // Delay has started

        skip(Parameters.DELAY_DURATION);

        vm.expectRevert(
            abi.encodeWithSelector(XanV1.ImplementationNotRankedBest.selector, _OTHER_NEW_IMPL, _NEW_IMPL),
            address(_xanProxy)
        );
        _xanProxy.upgradeToAndCall({newImplementation: _NEW_IMPL, data: ""});
    }
}
