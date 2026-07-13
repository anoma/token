// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Test} from "forge-std/Test.sol";

import {PrepareXanV2Upgrade} from "../../script/PrepareXanV2Upgrade.s.sol";
import {Parameters} from "../../src/libs/Parameters.sol";
import {XanGovernor} from "../../src/XanGovernor.sol";
import {XanUpgradeCouncilModule} from "../../src/XanUpgradeCouncilModule.sol";
import {XanV1} from "../../src/XanV1.sol";

/// @notice Pins the production governance wiring produced by `PrepareXanV2Upgrade.deployGovernance`. It establishes
/// the entire security posture of the layer — who may schedule and cancel, that execution is permissionless, and that
/// no residual deployer privilege survives — so every role assignment is asserted here explicitly.
contract PrepareXanV2UpgradeTest is Test {
    address internal immutable _COUNCIL_MULTISIG = makeAddr("councilMultisig");

    PrepareXanV2Upgrade internal _script;
    address internal _deployer;
    address internal _token;
    XanGovernor internal _governor;
    TimelockController internal _timelock;
    XanUpgradeCouncilModule internal _module;

    function setUp() public {
        _token = Upgrades.deployUUPSProxy(
            "XanV1.sol:XanV1", abi.encodeCall(XanV1.initializeV1, (makeAddr("mintRecipient"), _COUNCIL_MULTISIG))
        );

        _script = new PrepareXanV2Upgrade();
        _deployer = address(_script);
        // `deployGovernance` makes `msg.sender` the transient timelock admin and wires the roles as the script itself,
        // so it must be called with the script pranked as the sender.
        vm.prank(_deployer);
        (address governor, address timelock, address councilModule) =
            _script.deployGovernance({token: _token, councilMultisig: _COUNCIL_MULTISIG});

        _governor = XanGovernor(payable(governor));
        _timelock = TimelockController(payable(timelock));
        _module = XanUpgradeCouncilModule(councilModule);
    }

    function test_deployGovernance_reverts_if_the_token_is_the_zero_address() public {
        vm.expectRevert(PrepareXanV2Upgrade.InvalidTokenAddress.selector, address(_script));
        _script.deployGovernance({token: address(0), councilMultisig: _COUNCIL_MULTISIG});
    }

    function test_deployGovernance_reverts_if_the_council_is_the_zero_address() public {
        vm.expectRevert(PrepareXanV2Upgrade.InvalidCouncilAddress.selector, address(_script));
        _script.deployGovernance({token: _token, councilMultisig: address(0)});
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

    function test_run_deploys_governance_and_prepares_the_upgrade() public {
        (address implV2, address governor, address timelock, address councilModule) =
            _script.run({proxy: _token, councilMultisig: _COUNCIL_MULTISIG});

        // The governance stack is deployed and wired; the V2 implementation is prepared.
        assertTrue(implV2 != address(0), "implV2 not prepared");
        assertEq(address(XanGovernor(payable(governor)).token()), _token, "governor not driven by the proxy");
        assertEq(XanGovernor(payable(governor)).timelock(), timelock, "governor not wired to the timelock");
        assertEq(XanUpgradeCouncilModule(councilModule).owner(), timelock, "upgrade council not owned by the timelock");

        // `run` does not schedule — the V1 council Safe schedules the returned `implV2` in a separate transaction.
        (address scheduledImpl,) = XanV1(_token).scheduledCouncilUpgrade();
        assertEq(scheduledImpl, address(0), "run must not schedule the upgrade");
    }

    function test_deployGovernance_grants_scheduling_and_cancelling_to_the_governor_and_the_upgrade_council()
        public
        view
    {
        bytes32 proposerRole = _timelock.PROPOSER_ROLE();
        bytes32 cancellerRole = _timelock.CANCELLER_ROLE();

        assertTrue(_timelock.hasRole(proposerRole, address(_governor)));
        assertTrue(_timelock.hasRole(cancellerRole, address(_governor)));
        assertTrue(_timelock.hasRole(proposerRole, address(_module)));
        assertTrue(_timelock.hasRole(cancellerRole, address(_module)));

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
        assertFalse(_timelock.hasRole(adminRole, address(_module)));
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
        assertEq(_module.owner(), address(_timelock));
        assertEq(_module.getCouncil(), _COUNCIL_MULTISIG);
        assertEq(
            _module.cancelWindow(),
            uint256(Parameters.VOTING_DELAY) + Parameters.VOTING_PERIOD + Parameters.DELAY_DURATION
                + Parameters.COUNCIL_CANCEL_BUFFER
        );
    }
}
