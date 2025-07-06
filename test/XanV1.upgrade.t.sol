// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {Upgrades, UnsafeUpgrades, Options} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Test} from "forge-std/Test.sol";

import {XanV2} from "../src/drafts/XanV2.sol";
import {Parameters} from "../src/libs/Parameters.sol";
import {XanV1} from "../src/XanV1.sol";

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
        vm.expectRevert(abi.encodeWithSelector(XanV1.DelayPeriodNotStarted.selector), address(_xanProxy));
        _xanProxy.upgradeToAndCall({newImplementation: _voterProposedImpl, data: ""});
    }

    function test_authorizeUpgrade_reverts_voter_body_upgrade_if_the_delay_period_has_passed_for_a_different_implementation(
    ) public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_voterProposedImpl2);
        vm.stopPrank();

        _xanProxy.startVoterBodyUpgradeDelay(_voterProposedImpl2);
        skip(Parameters.DELAY_DURATION);

        vm.expectRevert(
            abi.encodeWithSelector(XanV1.ImplementationNotDelayed.selector, _voterProposedImpl2, _voterProposedImpl),
            address(_xanProxy)
        );
        _xanProxy.upgradeToAndCall({newImplementation: _voterProposedImpl, data: ""});
    }

    function test_authorizeUpgrade_reverts_voter_body_upgrade_if_delay_period_has_not_started() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(_xanProxy.calculateQuorumThreshold() + 1);
        _xanProxy.castVote(_voterProposedImpl);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(XanV1.DelayPeriodNotStarted.selector), address(_xanProxy));
        _xanProxy.upgradeToAndCall({newImplementation: _voterProposedImpl, data: ""});
    }

    function test_authorizeUpgrade_reverts_voter_body_upgrade_if_delay_period_has_not_ended() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_voterProposedImpl);
        vm.stopPrank();

        _xanProxy.startVoterBodyUpgradeDelay(_voterProposedImpl);

        vm.expectRevert(abi.encodeWithSelector(XanV1.DelayPeriodNotEnded.selector), address(_xanProxy));
        _xanProxy.upgradeToAndCall({newImplementation: _voterProposedImpl, data: ""});
    }

    function test_authorizeUpgrade_reverts_voter_body_upgrade_if_quorum_is_not_met() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_voterProposedImpl);
        vm.stopPrank();

        _xanProxy.startVoterBodyUpgradeDelay(_voterProposedImpl);
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

        _xanProxy.startVoterBodyUpgradeDelay(_voterProposedImpl);
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

    function test_authorizeUpgrade_reverts_council_upgrade_if_voter_body_implementation_has_reached_quorum() public {
        // Voter body votes on `_voterProposedImpl`
        vm.startPrank(_defaultSender);
        _xanProxy.lock(_xanProxy.unlockedBalanceOf(_defaultSender));
        _xanProxy.castVote(_voterProposedImpl);
        vm.stopPrank();

        // Start upgrade delay for `_voterProposedImpl`
        _xanProxy.startVoterBodyUpgradeDelay(_voterProposedImpl);

        // Council proposes `_councilProposedImpl`
        vm.prank(_COUNCIL);
        _xanProxy.proposeCouncilUpgrade(_councilProposedImpl);

        // Advance time after the delay end of the implementation proposed by the council.
        skip(_xanProxy.councilDelayEndTime());

        // Try to upgrade to which should fail
        vm.expectRevert(
            abi.encodeWithSelector(XanV1.QuorumReachedForVoterBodyProposedImplementation.selector, _voterProposedImpl),
            address(_xanProxy)
        );
        _xanProxy.upgradeToAndCall({newImplementation: _councilProposedImpl, data: ""});
    }

    function test_authorizeUpgrade_passes_if_the_council_and_voter_body_have_proposed_the_same_implementation()
        public
    {
        // Voter body votes on `_voterProposedImpl`
        vm.startPrank(_defaultSender);
        _xanProxy.lock(_xanProxy.unlockedBalanceOf(_defaultSender));
        _xanProxy.castVote(_voterProposedImpl);
        vm.stopPrank();

        // Start upgrade delay for `_voterProposedImpl`
        _xanProxy.startVoterBodyUpgradeDelay(_voterProposedImpl);

        // Council proposes `_voterProposedImpl` as well
        vm.prank(_COUNCIL);
        _xanProxy.proposeCouncilUpgrade(_voterProposedImpl);

        // Advance time after the delay end of the implementation proposed by the council.
        skip(_xanProxy.councilDelayEndTime());

        // Upgrade which should pass
        vm.expectEmit(address(_xanProxy));
        emit IERC1967.Upgraded(_voterProposedImpl);
        _xanProxy.upgradeToAndCall({newImplementation: _voterProposedImpl, data: ""});
    }

    function test_upgradeToAndCall_emits_the_Upgraded_event() public {
        vm.prank(_COUNCIL);
        _xanProxy.proposeCouncilUpgrade(_councilProposedImpl);

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
        _xanProxy.proposeCouncilUpgrade(_councilProposedImpl);

        skip(Parameters.DELAY_DURATION);

        vm.expectEmit(address(_xanProxy));
        emit IERC1967.Upgraded(_councilProposedImpl);

        address(_xanProxy).upgradeProxy({
            newImpl: _councilProposedImpl,
            data: abi.encodeCall(XanV2.reinitializeFromV1, (address(uint160(1))))
        });

        // TODO! ASK CHRIS: Is this desired?
        assertEq(_xanProxy.governanceCouncil(), address(0));
    }

    function test_upgradeToAndCall_allows_upgrade_to_the_current_implementation() public {
        address currentImpl = _xanProxy.implementation();

        vm.prank(_COUNCIL);
        _xanProxy.proposeCouncilUpgrade(currentImpl);

        skip(Parameters.DELAY_DURATION);

        vm.expectEmit(address(_xanProxy));
        emit IERC1967.Upgraded(currentImpl);
        address(_xanProxy).upgradeProxy({newImpl: currentImpl, data: ""});
    }
}
