// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IXanVesting} from "../../src/interfaces/IXanVesting.sol";
import {XanVesting} from "../../src/XanVesting.sol";
import {XanV2Fixture} from "./XanV2Fixture.sol";

/// @notice Deploys an unfunded `XanVesting` on the XAN token of `XanV2Fixture`, with two recipients whose principals
/// do not divide evenly.
abstract contract XanVestingFixture is XanV2Fixture {
    uint256 internal constant _PRINCIPAL = 1_000_000e18;

    address internal immutable _ALICE = makeAddr("alice");
    address internal immutable _BOB = makeAddr("bob");

    IERC20 internal _xan;
    XanVesting internal _vesting;

    function setUp() public virtual override {
        super.setUp();
        _xan = IERC20(address(_xanV2Proxy));

        IXanVesting.Recipient[] memory recipients = new IXanVesting.Recipient[](2);
        recipients[0] = IXanVesting.Recipient({account: _ALICE, principal: _PRINCIPAL});
        recipients[1] = IXanVesting.Recipient({account: _BOB, principal: _PRINCIPAL / 3});
        _vesting = _deployVesting(recipients);
    }

    function _deployVesting(IXanVesting.Recipient[] memory recipients) internal returns (XanVesting vesting) {
        vesting = new XanVesting({xanToken: _xan, initialOwner: makeAddr("owner"), recipients: recipients});
    }

    /// @dev Unlocks for both recipients and checks that each receives its whole unlockable balance.
    function _unlockAll() internal {
        address[2] memory accounts = [_ALICE, _BOB];
        for (uint256 i = 0; i < accounts.length; ++i) {
            uint256 unlockable = _vesting.unlockableBalanceOf(accounts[i]);
            if (unlockable == 0) continue;

            vm.prank(accounts[i]);
            assertEq(_vesting.unlock(), unlockable);
        }
    }
}
