// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {Upgrades, UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";

import {Test} from "forge-std/Test.sol";

import {Parameters} from "../src/libs/Parameters.sol";
import {IXanV1, XanV1} from "../src/XanV1.sol";

contract XanV1CouncilTest is Test {
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

    function test_scheduleCouncilUpgrade_reverts_if_the_caller_is_not_the_council() public {
        vm.prank(_defaultSender);
        vm.expectRevert(abi.encodeWithSelector(XanV1.UnauthorizedCaller.selector, _defaultSender), address(_xanProxy));
        _xanProxy.scheduleCouncilUpgrade(_NEW_IMPL);
    }

    function test_scheduleCouncilUpgrade_reverts_if_an_voter_body_upgrade_has_quorum_and_the_minimal_locked_supply_is_reached(
    ) public {
        // Voter body votes on `_NEW_IMPL`
        vm.startPrank(_defaultSender);
        _xanProxy.lock(_xanProxy.unlockedBalanceOf(_defaultSender));
        _xanProxy.castVote(_NEW_IMPL);
        vm.stopPrank();
        // Schedule the `_NEW_IMPL`
        _xanProxy.scheduleVoterBodyUpgrade();

        // Attempt to schedule an council upgrade.
        vm.prank(_COUNCIL);
        vm.expectRevert(
            abi.encodeWithSelector(XanV1.QuorumAndMinLockedSupplyReached.selector, _NEW_IMPL), address(_xanProxy)
        );
        _xanProxy.scheduleCouncilUpgrade(_OTHER_NEW_IMPL);
    }

    function test_scheduleCouncilUpgrade_reverts_if_an_voter_body_upgrade_has_quorum_and_the_minimal_locked_supply_is_reached_even_if_it_is_the_same_implementation(
    ) public {
        // Voter body votes on `_NEW_IMPL`
        vm.startPrank(_defaultSender);
        _xanProxy.lock(_xanProxy.unlockedBalanceOf(_defaultSender));
        _xanProxy.castVote(_NEW_IMPL);
        vm.stopPrank();
        // Schedule the `_NEW_IMPL`
        _xanProxy.scheduleVoterBodyUpgrade();

        // Attempt to schedule an council upgrade.
        vm.prank(_COUNCIL);
        vm.expectRevert(
            abi.encodeWithSelector(XanV1.QuorumAndMinLockedSupplyReached.selector, _NEW_IMPL), address(_xanProxy)
        );
        _xanProxy.scheduleCouncilUpgrade(_NEW_IMPL);
    }

    function test_scheduleCouncilUpgrade_reverts_if_an_council_upgrade_has_been_proposed_already() public {
        vm.startPrank(_COUNCIL);

        uint48 endTime = Time.timestamp() + Parameters.DELAY_DURATION;
        _xanProxy.scheduleCouncilUpgrade(_NEW_IMPL);

        vm.expectRevert(
            abi.encodeWithSelector(XanV1.UpgradeAlreadyScheduled.selector, _NEW_IMPL, endTime), address(_xanProxy)
        );
        _xanProxy.scheduleCouncilUpgrade(_NEW_IMPL);
    }

    function test_scheduleCouncilUpgrade_proposes_an_upgrade_to_the_same_implementation() public {
        vm.startPrank(_COUNCIL);
        _xanProxy.scheduleCouncilUpgrade(_NEW_IMPL);
    }

    function test_scheduleCouncilUpgrade_proposes_an_upgrade() public {
        vm.prank(_COUNCIL);
        _xanProxy.scheduleCouncilUpgrade(_NEW_IMPL);
    }

    function test_scheduleCouncilUpgrade_emits_the_CouncilUpgradeScheduled_event() public {
        vm.prank(_COUNCIL);
        vm.expectEmit(address(_xanProxy));
        emit IXanV1.CouncilUpgradeScheduled({impl: _NEW_IMPL, endTime: Time.timestamp() + Parameters.DELAY_DURATION});
        _xanProxy.scheduleCouncilUpgrade(_NEW_IMPL);
    }

    function test_cancelCouncilUpgrade_reverts_if_the_caller_is_not_the_council() public {
        vm.prank(_COUNCIL);
        _xanProxy.scheduleCouncilUpgrade(_NEW_IMPL);

        vm.prank(_defaultSender);
        vm.expectRevert(abi.encodeWithSelector(XanV1.UnauthorizedCaller.selector, _defaultSender), address(_xanProxy));
        _xanProxy.cancelCouncilUpgrade();
    }

    function test_cancelCouncilUpgrade_cancels_the_upgrade_proposed_by_the_council() public {
        vm.startPrank(_COUNCIL);
        _xanProxy.scheduleCouncilUpgrade(_NEW_IMPL);
        _xanProxy.cancelCouncilUpgrade();
    }

    function test_cancelCouncilUpgrade_emits_the_CouncilUpgradeCancelled_event() public {
        vm.startPrank(_COUNCIL);
        _xanProxy.scheduleCouncilUpgrade(_NEW_IMPL);

        vm.expectEmit(address(_xanProxy));
        emit IXanV1.CouncilUpgradeCancelled(_NEW_IMPL);
        _xanProxy.cancelCouncilUpgrade();

        (address impl, uint48 endTime) = _xanProxy.scheduledVoterBodyUpgrade();
        assertEq(impl, address(0));
        assertEq(endTime, 0);
    }

    function test_vetoCouncilUpgrade_reverts_if_no_implementation_proposed_by_the_voter_body_has_reached_quorum()
        public
    {
        vm.prank(_COUNCIL);
        _xanProxy.scheduleCouncilUpgrade(_NEW_IMPL);

        // Vote for another implementation but without meeting the minimal locked supply
        vm.startPrank(_defaultSender);
        // Lock first half.
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY - 1);
        _xanProxy.castVote(_OTHER_NEW_IMPL);
        vm.stopPrank();

        vm.prank(_defaultSender);
        vm.expectRevert(
            abi.encodeWithSelector(
                XanV1.QuorumOrMinLockedSupplyNotReached.selector, _xanProxy.proposedImplementationByRank(0)
            ),
            address(_xanProxy)
        );
        _xanProxy.vetoCouncilUpgrade();
    }

    function test_vetoCouncilUpgrade_vetos_the_council_upgrade_before_the_delay_has_passed() public {
        // Schedule `_NEW_IMPL` as the council.
        vm.prank(_COUNCIL);
        _xanProxy.scheduleCouncilUpgrade(_NEW_IMPL);
        (address impl, uint48 endTime) = _xanProxy.scheduledCouncilUpgrade();

        // Ensure that `_OTHER_NEW_IMPL` has quorum.
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_OTHER_NEW_IMPL);
        vm.stopPrank();

        // Ensure that the delay has NOT passed.
        assertLt(Time.timestamp() + 24 hours, endTime);

        vm.expectEmit(address(_xanProxy));
        emit IXanV1.CouncilUpgradeVetoed(impl);
        _xanProxy.vetoCouncilUpgrade();
    }

    function test_vetoCouncilUpgrade_vetos_the_council_upgrade_after_the_delay_has_passed() public {
        // Schedule `_NEW_IMPL` as the council.
        vm.prank(_COUNCIL);
        _xanProxy.scheduleCouncilUpgrade(_NEW_IMPL);
        (address impl, uint48 endTime) = _xanProxy.scheduledCouncilUpgrade();

        // Ensure that `_OTHER_NEW_IMPL` has quorum.
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_OTHER_NEW_IMPL);
        vm.stopPrank();

        // Ensure that the delay has just passed.
        skip(Parameters.DELAY_DURATION + 1);
        assertGt(Time.timestamp(), endTime);

        // Veto the council upgrade
        vm.expectEmit(address(_xanProxy));
        emit IXanV1.CouncilUpgradeVetoed(impl);
        _xanProxy.vetoCouncilUpgrade();
    }

    function test_vetoCouncilUpgrade_emits_the_CouncilUpgradeVetoed_event() public {
        vm.prank(_COUNCIL);
        _xanProxy.scheduleCouncilUpgrade(_NEW_IMPL);

        // Reach quorum for another implementation.
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_OTHER_NEW_IMPL);
        vm.stopPrank();

        vm.expectEmit(address(_xanProxy));
        emit IXanV1.CouncilUpgradeVetoed(_NEW_IMPL);
        _xanProxy.vetoCouncilUpgrade();
    }

    function test_scheduledCouncilImplementation_returns_the_scheduled_upgrade_if_an_upgrade_has_been_scheduled()
        public
    {
        uint256 expectedEndTime = block.timestamp + Parameters.DELAY_DURATION;
        vm.prank(_COUNCIL);
        _xanProxy.scheduleCouncilUpgrade(_NEW_IMPL);

        (address impl, uint48 endTime) = _xanProxy.scheduledCouncilUpgrade();
        assertEq(impl, _NEW_IMPL);
        assertEq(endTime, expectedEndTime);
    }

    function test_scheduledCouncilImplementation_returns_0_if_no_upgrade_delay_has_been_started() public view {
        (address impl, uint48 endTime) = _xanProxy.scheduledCouncilUpgrade();
        assertEq(impl, address(0));
        assertEq(endTime, 0);
    }
}
