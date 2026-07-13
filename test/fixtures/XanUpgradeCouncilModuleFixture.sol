// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

import {Parameters} from "../../src/libs/Parameters.sol";
import {XanUpgradeCouncilModule} from "../../src/XanUpgradeCouncilModule.sol";
import {XanGovernorFixture} from "./XanGovernorFixture.sol";

/// @notice Extends the governor fixture with a wired `XanUpgradeCouncilModule`: the module is granted the timelock's
/// `PROPOSER` and `CANCELLER` roles, so the council can schedule token upgrades (and withdraw its own pending one) and
/// the voter body can cancel the council. Mirrors a real deployment where the token is owned by the timelock.
abstract contract XanUpgradeCouncilModuleFixture is XanGovernorFixture {
    /// @notice The upgrade council multisig.
    address internal immutable _COUNCIL_MULTISIG = makeAddr("upgradeCouncilMultisig");

    XanUpgradeCouncilModule internal _module;

    function setUp() public virtual override {
        super.setUp();

        _module = new XanUpgradeCouncilModule({
            governor: IGovernor(address(_governor)),
            timelock: _timelock,
            council: _COUNCIL_MULTISIG,
            token: address(_xanToken),
            cancelBuffer: Parameters.COUNCIL_CANCEL_BUFFER
        });

        // The base fixture renounced the deployer's timelock admin, so roles are now changed only through the timelock
        // itself; impersonating it here stands in for the governance proposal that would grant these roles in prod.
        vm.startPrank(address(_timelock));
        _timelock.grantRole(_timelock.PROPOSER_ROLE(), address(_module));
        _timelock.grantRole(_timelock.CANCELLER_ROLE(), address(_module));
        vm.stopPrank();
    }
}
