// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Test} from "forge-std/Test.sol";

import {ScheduleXanV1Upgrade} from "../../script/ScheduleXanV1Upgrade.s.sol";
import {Parameters} from "../../src/libs/Parameters.sol";
import {XanGovernor} from "../../src/XanGovernor.sol";
import {XanUpgradeCouncil} from "../../src/XanUpgradeCouncil.sol";
import {XanV1} from "../../src/XanV1.sol";

/// @notice Pins the production governance wiring produced by `ScheduleXanV1Upgrade.deployGovernance`. It establishes
/// the entire security posture of the layer — who may schedule and cancel, that execution is permissionless, and that
/// no residual deployer privilege survives — so every role assignment is asserted here explicitly.
contract ScheduleXanV1UpgradeTest is Test {
    address internal immutable _COUNCIL_MULTISIG = makeAddr("councilMultisig");

    ScheduleXanV1Upgrade internal _script;
    address internal _deployer;
    address internal _token;
    XanGovernor internal _governor;
    TimelockController internal _timelock;
    XanUpgradeCouncil internal _upgradeCouncil;

    function setUp() public {
        _token = Upgrades.deployUUPSProxy(
            "XanV1.sol:XanV1", abi.encodeCall(XanV1.initializeV1, (makeAddr("mintRecipient"), makeAddr("v1Council")))
        );

        _script = new ScheduleXanV1Upgrade();
        _deployer = address(_script);
        (address governor, address timelock, address upgradeCouncil) =
            _script.deployGovernance({token: _token, councilMultisig: _COUNCIL_MULTISIG, deployer: _deployer});

        _governor = XanGovernor(payable(governor));
        _timelock = TimelockController(payable(timelock));
        _upgradeCouncil = XanUpgradeCouncil(upgradeCouncil);
    }

    function test_deployGovernance_reverts_if_the_token_is_the_zero_address() public {
        vm.expectRevert(ScheduleXanV1Upgrade.InvalidTokenAddress.selector, address(_script));
        _script.deployGovernance({token: address(0), councilMultisig: _COUNCIL_MULTISIG, deployer: address(_script)});
    }

    function test_deployGovernance_reverts_if_the_council_is_the_zero_address() public {
        vm.expectRevert(ScheduleXanV1Upgrade.InvalidCouncilAddress.selector, address(_script));
        _script.deployGovernance({token: _token, councilMultisig: address(0), deployer: address(_script)});
    }

    function testFuzz_grantRole_reverts_if_the_caller_is_not_the_timelock(address caller) public {
        vm.assume(caller != address(_timelock));

        bytes32 proposerRole = _timelock.PROPOSER_ROLE();
        bytes32 adminRole = _timelock.DEFAULT_ADMIN_ROLE();

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, adminRole),
            address(_timelock)
        );
        _timelock.grantRole(proposerRole, caller);
    }

    function test_run_deploys_governance_and_schedules_the_upgrade() public {
        // `run` schedules through the broadcast sender, so the V1 council must be that sender (`DEFAULT_SENDER`).
        address proxy = Upgrades.deployUUPSProxy(
            "XanV1.sol:XanV1", abi.encodeCall(XanV1.initializeV1, (makeAddr("mintRecipient"), DEFAULT_SENDER))
        );

        (address implV2, address governor, address timelock, address upgradeCouncil) =
            _script.run({proxy: proxy, councilMultisig: _COUNCIL_MULTISIG});

        // The governance stack is deployed and wired to the token and timelock.
        assertEq(address(XanGovernor(payable(governor)).token()), proxy, "governor not driven by the proxy");
        assertEq(XanGovernor(payable(governor)).timelock(), timelock, "governor not wired to the timelock");
        assertEq(XanUpgradeCouncil(upgradeCouncil).owner(), timelock, "upgrade council not owned by the timelock");

        // The V2 implementation is scheduled through the V1 council for after the council delay.
        (address scheduledImpl, uint48 endTime) = XanV1(proxy).scheduledCouncilUpgrade();
        assertEq(scheduledImpl, implV2, "run did not schedule implV2");
        assertEq(endTime, Time.timestamp() + Parameters.DELAY_DURATION, "unexpected upgrade delay");
    }

    function test_run_reverts_if_the_caller_is_not_the_v1_council() public {
        address proxy = Upgrades.deployUUPSProxy(
            "XanV1.sol:XanV1", abi.encodeCall(XanV1.initializeV1, (makeAddr("mintRecipient"), makeAddr("otherCouncil")))
        );

        vm.expectRevert(abi.encodeWithSelector(XanV1.UnauthorizedCaller.selector, DEFAULT_SENDER), address(proxy));
        _script.run({proxy: proxy, councilMultisig: _COUNCIL_MULTISIG});
    }

    function test_deployGovernance_grants_scheduling_and_cancelling_to_the_governor_and_the_upgrade_council()
        public
        view
    {
        bytes32 proposerRole = _timelock.PROPOSER_ROLE();
        bytes32 cancellerRole = _timelock.CANCELLER_ROLE();

        assertTrue(_timelock.hasRole(proposerRole, address(_governor)));
        assertTrue(_timelock.hasRole(cancellerRole, address(_governor)));
        assertTrue(_timelock.hasRole(proposerRole, address(_upgradeCouncil)));
        assertTrue(_timelock.hasRole(cancellerRole, address(_upgradeCouncil)));

        // Neither the council multisig nor the token hold timelock roles directly — all council power flows through
        // the upgrade council's narrow interface.
        assertFalse(_timelock.hasRole(proposerRole, _COUNCIL_MULTISIG));
        assertFalse(_timelock.hasRole(cancellerRole, _COUNCIL_MULTISIG));
        assertFalse(_timelock.hasRole(proposerRole, _token));
    }

    /// @notice Anyone may execute a ready operation: authority lives entirely in scheduling and cancelling.
    function test_deployGovernance_opens_the_executor_role() public view {
        assertTrue(_timelock.hasRole(_timelock.EXECUTOR_ROLE(), address(0)));
    }

    function test_deployGovernance_leaves_the_timelock_self_administered() public view {
        bytes32 adminRole = _timelock.DEFAULT_ADMIN_ROLE();

        assertTrue(_timelock.hasRole(adminRole, address(_timelock)));

        // No deployer-side account retains admin: not the deployer, not the test contract, and none of the wired
        // contracts.
        assertFalse(_timelock.hasRole(adminRole, _deployer));
        assertFalse(_timelock.hasRole(adminRole, address(this)));
        assertFalse(_timelock.hasRole(adminRole, address(_governor)));
        assertFalse(_timelock.hasRole(adminRole, address(_upgradeCouncil)));
    }

    function test_deployGovernance_sets_the_timelock_min_delay() public view {
        assertEq(_timelock.getMinDelay(), Parameters.DELAY_DURATION);
    }

    function test_deployGovernance_configures_the_governor() public view {
        assertEq(address(_governor.token()), _token);
        assertEq(_governor.timelock(), address(_timelock));
        assertEq(_governor.votingDelay(), Parameters.VOTING_DELAY);
        assertEq(_governor.votingPeriod(), Parameters.VOTING_PERIOD);
        assertEq(_governor.proposalThreshold(), Parameters.PROPOSAL_THRESHOLD);
        assertEq(
            _governor.quorumNumerator(), Parameters.QUORUM_RATIO_NUMERATOR * 100 / Parameters.QUORUM_RATIO_DENOMINATOR
        );
    }

    function test_quorum_numerator_is_checkpointed_at_the_deploy_timestamp() public view {
        uint48 deployTimestamp = Time.timestamp();
        uint256 expectedNumerator = Parameters.QUORUM_RATIO_NUMERATOR * 100 / Parameters.QUORUM_RATIO_DENOMINATOR;

        assertEq(_governor.quorumNumerator(deployTimestamp), expectedNumerator, "numerator not set at deploy timestamp");
        assertEq(_governor.quorumNumerator(deployTimestamp - 1), 0, "checkpoint exists before the deploy timestamp");
    }

    function test_deployGovernance_wires_the_upgrade_council() public view {
        assertEq(_upgradeCouncil.owner(), address(_timelock));
        assertEq(_upgradeCouncil.council(), _COUNCIL_MULTISIG);
        assertEq(
            _upgradeCouncil.cancelWindow(),
            uint256(Parameters.VOTING_DELAY) + Parameters.VOTING_PERIOD + Parameters.DELAY_DURATION
                + Parameters.COUNCIL_CANCEL_BUFFER
        );
    }
}
