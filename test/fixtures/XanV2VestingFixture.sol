// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";

import {XAN_V2_VESTING_PROXY} from "../../script/DeployXanV2Vesting.s.sol";
import {IXanV2Vesting} from "../../src/interfaces/IXanV2Vesting.sol";
import {XanV2Vesting} from "../../src/XanV2Vesting.sol";
import {XanV2Fixture} from "./XanV2Fixture.sol";

/// @notice Deploys an unfunded `XanV2Vesting` proxy on the XAN token of `XanV2Fixture`, with the recipients of
/// `_initialRecipients`.
abstract contract XanV2VestingFixture is XanV2Fixture {
    uint256 internal constant _PRINCIPAL = 1_000_000e18;

    address internal immutable _ALICE = makeAddr("alice");
    address internal immutable _BOB = makeAddr("bob");
    address internal immutable _OWNER = makeAddr("owner");

    IERC20 internal _xan;
    XanV2Vesting internal _vesting;

    function setUp() public virtual override {
        super.setUp();
        _xan = IERC20(address(_xanV2Proxy));
        _vesting = _deployVesting(_initialRecipients());
    }

    function _deployVesting(IXanV2Vesting.Recipient[] memory recipients) internal returns (XanV2Vesting vesting) {
        vesting = XanV2Vesting(
            UnsafeUpgrades.deployUUPSProxy({
                impl: address(new XanV2Vesting(_xan)), initializerData: _initData(recipients)
            })
        );
    }

    /// @dev Deploys a proxy with the recipients of `_initialRecipients` at the address of Ethereum mainnet and Sepolia.
    function _deployPinnedVesting() internal returns (XanV2Vesting vesting) {
        deployCodeTo({
            what: "ERC1967Proxy.sol:ERC1967Proxy",
            args: abi.encode(address(new XanV2Vesting(_xan)), _initData(_initialRecipients())),
            where: XAN_V2_VESTING_PROXY
        });
        vesting = XanV2Vesting(XAN_V2_VESTING_PROXY);
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

    /// @notice The recipients of `_vesting`: two whose principals do not divide evenly. Override to customize.
    function _initialRecipients() internal view virtual returns (IXanV2Vesting.Recipient[] memory recipients) {
        recipients = new IXanV2Vesting.Recipient[](2);
        recipients[0] = IXanV2Vesting.Recipient({account: _ALICE, principal: _PRINCIPAL});
        recipients[1] = IXanV2Vesting.Recipient({account: _BOB, principal: _PRINCIPAL / 3});
    }

    function _initData(IXanV2Vesting.Recipient[] memory recipients) internal view returns (bytes memory data) {
        data = abi.encodeCall(XanV2Vesting.initialize, (_OWNER, recipients));
    }

    function _recipients(address account, uint256 principal)
        internal
        pure
        returns (IXanV2Vesting.Recipient[] memory recipients)
    {
        recipients = new IXanV2Vesting.Recipient[](1);
        recipients[0] = IXanV2Vesting.Recipient({account: account, principal: principal});
    }
}
