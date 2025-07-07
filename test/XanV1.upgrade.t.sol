// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {Upgrades, UnsafeUpgrades, Options} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Test} from "forge-std/Test.sol";

import {XanV2} from "../src/drafts/XanV2.sol";
import {Parameters} from "../src/libs/Parameters.sol";
import {IXanV1, XanV1} from "../src/XanV1.sol";

contract XanV1UpgradeTest is Test {
    using UnsafeUpgrades for address;
    using ERC1967Utils for address;

    address internal constant _COUNCIL = address(uint160(1));

    address internal _defaultSender;
    address internal _voterProposedImpl;
    address internal _voterProposedImpl2;
    address internal _councilProposedImpl;
    XanV1 internal _xanProxy;

    function setUp() public {
        (, _defaultSender,) = vm.readCallers();

        // Deploy proxy and mint tokens for the `_defaultSender`.
        vm.prank(_defaultSender);
        _xanProxy = XanV1(
            Upgrades.deployUUPSProxy({
                contractName: "XanV1.sol:XanV1",
                initializerData: abi.encodeCall(XanV1.initializeV1, (_defaultSender, _COUNCIL))
            })
        );

        Options memory opts;
        _voterProposedImpl = Upgrades.prepareUpgrade({contractName: "XanV2.sol:XanV2", opts: opts});
        _voterProposedImpl2 = Upgrades.prepareUpgrade({contractName: "XanV2.sol:XanV2", opts: opts});
        _councilProposedImpl = Upgrades.prepareUpgrade({contractName: "XanV2.sol:XanV2", opts: opts});
    }

    function test_authorizeUpgrade_reverts_for_an_upgrade_to_address_0() public {
        vm.expectRevert(abi.encodeWithSelector(XanV1.ImplementationZero.selector), address(_xanProxy));
        _xanProxy.upgradeToAndCall({newImplementation: address(0), data: ""});
    }

    function test_authorizeUpgrade_reverts_voter_body_upgrade_if_implementation_has_not_been_voted_on() public {
        vm.expectRevert(
            abi.encodeWithSelector(XanV1.UpgradeNotScheduled.selector, _voterProposedImpl), address(_xanProxy)
        );
        _xanProxy.upgradeToAndCall({newImplementation: _voterProposedImpl, data: ""});
    }

    function test_authorizeUpgrade_reverts_voter_body_upgrade_if_the_delay_period_has_passed_for_a_different_implementation(
    ) public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_voterProposedImpl2);
        vm.stopPrank();

        _xanProxy.scheduleVoterBodyUpgrade();
        skip(Parameters.DELAY_DURATION);

        vm.expectRevert(
            abi.encodeWithSelector(XanV1.UpgradeNotScheduled.selector, _voterProposedImpl), address(_xanProxy)
        );
        _xanProxy.upgradeToAndCall({newImplementation: _voterProposedImpl, data: ""});
    }

    function test_authorizeUpgrade_reverts_voter_body_upgrade_if_delay_period_has_not_started() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(_xanProxy.calculateQuorumThreshold() + 1);
        _xanProxy.castVote(_voterProposedImpl);
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(XanV1.UpgradeNotScheduled.selector, _voterProposedImpl), address(_xanProxy)
        );
        _xanProxy.upgradeToAndCall({newImplementation: _voterProposedImpl, data: ""});
    }

    function test_authorizeUpgrade_reverts_voter_body_upgrade_if_delay_period_has_not_ended() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_voterProposedImpl);
        vm.stopPrank();

        uint48 endTime = Time.timestamp() + Parameters.DELAY_DURATION;
        _xanProxy.scheduleVoterBodyUpgrade();

        vm.expectRevert(abi.encodeWithSelector(XanV1.DelayPeriodNotEnded.selector, endTime), address(_xanProxy));
        _xanProxy.upgradeToAndCall({newImplementation: _voterProposedImpl, data: ""});
    }

    function test_authorizeUpgrade_reverts_voter_body_upgrade_if_quorum_is_not_met() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_voterProposedImpl);
        vm.stopPrank();

        _xanProxy.scheduleVoterBodyUpgrade();
        skip(Parameters.DELAY_DURATION);

        vm.prank(_defaultSender);
        _xanProxy.revokeVote(_voterProposedImpl);

        vm.expectRevert(abi.encodeWithSelector(XanV1.QuorumNotReached.selector, _voterProposedImpl), address(_xanProxy));
        _xanProxy.upgradeToAndCall({newImplementation: _voterProposedImpl, data: ""});
    }

    function test_authorizeUpgrade_reverts_voter_body_upgrade_if_implementation_is_not_best_ranked() public {
        vm.startPrank(_defaultSender);

        uint256 quorumThreshold =
            (_xanProxy.totalSupply() * Parameters.QUORUM_RATIO_NUMERATOR) / Parameters.QUORUM_RATIO_DENOMINATOR;

        // Meet the quorum threshold with one excess vote.
        _xanProxy.lock(quorumThreshold + 1);
        _xanProxy.castVote(_voterProposedImpl);
        assertEq(_xanProxy.proposedImplementationByRank(0), _voterProposedImpl);

        _xanProxy.scheduleVoterBodyUpgrade();
        _xanProxy.lock(1);
        _xanProxy.castVote(_voterProposedImpl2);
        vm.stopPrank();

        assertEq(_xanProxy.proposedImplementationByRank(0), _voterProposedImpl2); // Delay has not started
        assertEq(_xanProxy.proposedImplementationByRank(1), _voterProposedImpl); // Delay has started

        skip(Parameters.DELAY_DURATION);

        vm.expectRevert(
            abi.encodeWithSelector(XanV1.ImplementationNotRankedBest.selector, _voterProposedImpl2, _voterProposedImpl),
            address(_xanProxy)
        );
        _xanProxy.upgradeToAndCall({newImplementation: _voterProposedImpl, data: ""});
    }

    function test_authorizeUpgrade_passes_if_the_voter_body_has_scheduled_the_upgrade_after_the_council() public {
        // Council proposes `_councilProposedImpl`
        vm.prank(_COUNCIL);
        _xanProxy.scheduleCouncilUpgrade(_councilProposedImpl);

        skip(1);

        // Voter body votes on `_councilProposedImpl` as well
        vm.startPrank(_defaultSender);
        _xanProxy.lock(_xanProxy.unlockedBalanceOf(_defaultSender));
        _xanProxy.castVote(_councilProposedImpl);
        vm.stopPrank();
        // Schedule the `_councilProposedImpl`
        _xanProxy.scheduleVoterBodyUpgrade();

        // Advance time after the end time of the scheduled voter body upgrade.
        (, uint48 endTime) = _xanProxy.scheduledVoterBodyUpgrade();
        skip(endTime);

        // Upgrade which should pass
        vm.expectEmit(address(_xanProxy));
        emit IERC1967.Upgraded(_councilProposedImpl);
        _xanProxy.upgradeToAndCall({newImplementation: _councilProposedImpl, data: ""});
    }

    function test_authorizeUpgrade_passes_if_the_voter_body_has_scheduled_the_upgrade_in_the_same_block_as_the_council_(
    ) public {
        // Council proposes `_councilProposedImpl`
        vm.prank(_COUNCIL);
        _xanProxy.scheduleCouncilUpgrade(_councilProposedImpl);

        // Voter body votes on `_councilProposedImpl` as well
        vm.startPrank(_defaultSender);
        _xanProxy.lock(_xanProxy.unlockedBalanceOf(_defaultSender));
        _xanProxy.castVote(_councilProposedImpl);
        vm.stopPrank();
        // Schedule the `_councilProposedImpl`
        _xanProxy.scheduleVoterBodyUpgrade();

        // Advance time after the end time of the scheduled voter body upgrade.
        (, uint48 endTime) = _xanProxy.scheduledVoterBodyUpgrade();
        skip(endTime);

        // Upgrade which should pass
        vm.expectEmit(address(_xanProxy));
        emit IERC1967.Upgraded(_councilProposedImpl);
        _xanProxy.upgradeToAndCall({newImplementation: _councilProposedImpl, data: ""});
    }

    function test_upgradeToAndCall_emits_the_Upgraded_event() public {
        vm.prank(_COUNCIL);
        _xanProxy.scheduleCouncilUpgrade(_councilProposedImpl);

        skip(Parameters.DELAY_DURATION);

        vm.expectEmit(address(_xanProxy));
        emit IERC1967.Upgraded(_councilProposedImpl);

        address(_xanProxy).upgradeProxy({
            newImpl: _councilProposedImpl,
            data: abi.encodeCall(XanV2.reinitializeFromV1, (address(uint160(1))))
        });
    }

    function test_upgradeToAndCall_resets_the_governance_council_address() public {
        vm.prank(_COUNCIL);
        _xanProxy.scheduleCouncilUpgrade(_councilProposedImpl);

        skip(Parameters.DELAY_DURATION);

        vm.expectEmit(address(_xanProxy));
        emit IERC1967.Upgraded(_councilProposedImpl);

        address(_xanProxy).upgradeProxy({
            newImpl: _councilProposedImpl,
            data: abi.encodeCall(XanV2.reinitializeFromV1, (address(uint160(1))))
        });

        // TODO! Confirm with Chris
        assertEq(_xanProxy.governanceCouncil(), address(0));
    }

    function test_upgradeToAndCall_allows_upgrade_to_the_current_implementation() public {
        address currentImpl = _xanProxy.implementation();

        vm.prank(_COUNCIL);
        _xanProxy.scheduleCouncilUpgrade(currentImpl);

        skip(Parameters.DELAY_DURATION);

        vm.expectEmit(address(_xanProxy));
        emit IERC1967.Upgraded(currentImpl);
        address(_xanProxy).upgradeProxy({newImpl: currentImpl, data: ""});
    }

    function invariant_mutually_exclusive_schedule_upgrades() public view {
        (address scheduledVoterBodyImpl,) = _xanProxy.scheduledVoterBodyUpgrade();
        (address scheduledCouncilImpl,) = _xanProxy.scheduledCouncilUpgrade();

        bool isScheduledByCouncil = scheduledVoterBodyImpl != address(0);
        bool isScheduledByVoterBody = scheduledCouncilImpl != address(0);

        assert(!(isScheduledByCouncil && isScheduledByVoterBody));
    }
}
