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

    function test_proposeCouncilUpgrade_reverts_if_the_caller_is_not_the_council() public {
        vm.prank(_defaultSender);
        vm.expectRevert(abi.encodeWithSelector(XanV1.UnauthorizedCaller.selector, _defaultSender), address(_xanProxy));
        _xanProxy.proposeCouncilUpgrade(_NEW_IMPL);
    }

    function test_proposeCouncilUpgrade_reverts_if_an_council_upgrade_has_been_proposed_already() public {
        vm.startPrank(_COUNCIL);
        _xanProxy.proposeCouncilUpgrade(_NEW_IMPL);

        vm.expectRevert(
            abi.encodeWithSelector(XanV1.ImplementationAlreadyProposed.selector, _NEW_IMPL), address(_xanProxy)
        );
        _xanProxy.proposeCouncilUpgrade(_NEW_IMPL);
    }

    function test_proposeCouncilUpgrade_proposes_an_upgrade_to_the_same_implementation() public {
        vm.startPrank(_COUNCIL);
        _xanProxy.proposeCouncilUpgrade(_NEW_IMPL);

        /*
         * Multisig can propose upgrades which will pass by default in the period (e.g. 2 weeks) if no quorum is reached for another upgrade (which could be just to stay with the current token implementation).
         */
        // TODO! Ask Chris
        // 1. Why do we want this?
        // 2. Should the upgrade reset all the votes?
    }

    function test_proposeCouncilUpgrade_proposes_an_upgrade() public {
        vm.prank(_COUNCIL);
        _xanProxy.proposeCouncilUpgrade(_NEW_IMPL);
    }

    function test_proposeCouncilUpgrade_emits_the_CouncilUpgradeProposed_event() public {
        uint48 currentTime = Time.timestamp();

        vm.prank(_COUNCIL);
        vm.expectEmit(address(_xanProxy));
        emit IXanV1.CouncilUpgradeProposed({
            implementation: _NEW_IMPL,
            startTime: currentTime,
            endTime: currentTime + Parameters.DELAY_DURATION
        });
        _xanProxy.proposeCouncilUpgrade(_NEW_IMPL);
    }

    function test_cancelCouncilUpgrade_reverts_if_the_caller_is_not_the_council() public {
        vm.prank(_COUNCIL);
        _xanProxy.proposeCouncilUpgrade(_NEW_IMPL);

        vm.prank(_defaultSender);
        vm.expectRevert(abi.encodeWithSelector(XanV1.UnauthorizedCaller.selector, _defaultSender), address(_xanProxy));
        _xanProxy.cancelCouncilUpgrade();
    }

    function test_cancelCouncilUpgrade_cancels_the_upgrade_proposed_by_the_council() public {
        vm.startPrank(_COUNCIL);
        _xanProxy.proposeCouncilUpgrade(_NEW_IMPL);
        _xanProxy.cancelCouncilUpgrade();
    }

    function test_cancelCouncilUpgrade_emits_the_CouncilUpgradeCancelled_event() public {
        vm.startPrank(_COUNCIL);
        _xanProxy.proposeCouncilUpgrade(_NEW_IMPL);

        vm.expectEmit(address(_xanProxy));
        emit IXanV1.CouncilUpgradeCancelled();
        _xanProxy.cancelCouncilUpgrade();
    }

    function test_vetoCouncilUpgrade_reverts_if_no_implementation_proposed_by_the_voter_body_has_reached_quorum()
        public
    {
        vm.prank(_COUNCIL);
        _xanProxy.proposeCouncilUpgrade(_NEW_IMPL);

        vm.prank(_defaultSender);
        vm.expectRevert(abi.encodeWithSelector(XanV1.QuorumNowhereReached.selector), address(_xanProxy));
        _xanProxy.vetoCouncilUpgrade();
    }

    function test_vetoCouncilUpgrade_vetos_the_council_upgrade() public {
        vm.prank(_COUNCIL);
        _xanProxy.proposeCouncilUpgrade(_NEW_IMPL);

        // Reach quorum for another implementation.
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_OTHER_NEW_IMPL);
        vm.stopPrank();

        _xanProxy.vetoCouncilUpgrade();

        // Check that the implementation has been reset.abi
        assertEq(_xanProxy.voterBodyProposedImplementation(), address(0));
    }

    function test_vetoCouncilUpgrade_emits_the_CouncilUpgradeVetoed_event() public {
        vm.prank(_COUNCIL);
        _xanProxy.proposeCouncilUpgrade(_NEW_IMPL);

        // Reach quorum for another implementation.
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_OTHER_NEW_IMPL);
        vm.stopPrank();

        vm.expectEmit(address(_xanProxy));
        emit IXanV1.CouncilUpgradeVetoed();
        _xanProxy.vetoCouncilUpgrade();
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

    function test_voterBodyProposedImplementation_returns_address_0_if_no_upgrade_delay_has_been_started()
        public
        view
    {
        assertEq(_xanProxy.voterBodyProposedImplementation(), address(0));
    }

    function test_councilProposedImplementation_returns_address_0_if_no_upgrade_delay_has_been_started() public view {
        assertEq(_xanProxy.councilProposedImplementation(), address(0));
    }
}
