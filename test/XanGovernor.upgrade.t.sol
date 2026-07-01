// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

import {Parameters} from "../src/libs/Parameters.sol";
import {MockXanV3} from "./mocks/MockXanV3.sol";
import {XanGovernorFixture} from "./XanGovernorFixture.sol";

/// @notice Demonstrates that the governor DAO can upgrade the `XanV2` token itself. Because the token's owner is the
/// timelock, only a passing proposal executed by the timelock can authorize a UUPS upgrade (`upgradeToAndCall`).
contract XanGovernorUpgradeTest is XanGovernorFixture {
    function test_direct_upgrade_by_a_non_owner_reverts() public {
        address newImpl = address(
            new MockXanV3(_v1Implementation, address(_timelock), Parameters.VESTING_START, Parameters.VESTING_DURATION)
        );

        vm.prank(_voter);
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, _voter), address(_xanToken)
        );
        _xanToken.upgradeToAndCall(newImpl, "");
    }

    function test_dao_upgrades_the_token_to_v3() public {
        address newImpl = address(
            new MockXanV3(_v1Implementation, address(_timelock), Parameters.VESTING_START, Parameters.VESTING_DURATION)
        );

        address[] memory targets = new address[](1);
        targets[0] = address(_xanToken);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (newImpl, ""));

        uint256 proposalId = _passProposal(targets, values, calldatas, "upgrade XAN to v3");

        // The proposal executed and the proxy now points at the new implementation.
        assertEq(uint8(_governor.state(proposalId)), uint8(IGovernor.ProposalState.Executed));
        assertEq(_xanToken.implementation(), newImpl);

        // The new V3 logic is reachable through the unchanged proxy address.
        assertEq(MockXanV3(address(_xanToken)).version(), 3);
    }

    function test_voter_votes_equal_balance() public view {
        // The voter self-delegates in the fixture, so its voting power tracks its full balance. Orthogonal to the
        // upgrade path, hence its own test.
        assertEq(_xanToken.getVotes(_voter), _xanToken.balanceOf(_voter));
    }
}
