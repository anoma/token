// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

import {Parameters} from "../../src/libs/Parameters.sol";
import {XanSecurityCouncil} from "../../src/XanSecurityCouncil.sol";
import {XanGovernorFixture} from "./XanGovernorFixture.sol";

/// @notice Extends the governor fixture with a wired `XanSecurityCouncil` module: the module is granted the timelock's
/// `PROPOSER` and `CANCELLER` roles, so the council can schedule and cancel token upgrades and the voter body can cancel
/// the council. Mirrors a real deployment where the token is owned by the timelock.
abstract contract XanSecurityCouncilFixture is XanGovernorFixture {
    /// @notice The security council multisig.
    address internal immutable _COUNCIL_MULTISIG = makeAddr("securityCouncilMultisig");

    XanSecurityCouncil internal _securityCouncil;

    function setUp() public virtual override {
        super.setUp();

        _securityCouncil = new XanSecurityCouncil({
            governor: IGovernor(address(_governor)),
            timelock: _timelock,
            token: address(_xanToken),
            initialCouncil: _COUNCIL_MULTISIG,
            cancelBuffer: Parameters.COUNCIL_CANCEL_BUFFER
        });

        // The base fixture renounced the deployer's timelock admin, so roles are now changed only through the timelock
        // itself; impersonating it here stands in for the governance proposal that would grant these roles in prod.
        vm.startPrank(address(_timelock));
        _timelock.grantRole(_timelock.PROPOSER_ROLE(), address(_securityCouncil));
        _timelock.grantRole(_timelock.CANCELLER_ROLE(), address(_securityCouncil));
        vm.stopPrank();
    }
}
