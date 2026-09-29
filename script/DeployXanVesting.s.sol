// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Script} from "forge-std/Script.sol";

import {IXanV2} from "../src/interfaces/IXanV2.sol";
import {IXanVesting} from "../src/interfaces/IXanVesting.sol";
import {XanVesting} from "../src/XanVesting.sol";

/// @notice Deploys `XanVesting` with the recipients of a JSON file, after it checks that no recipient has a principal
/// in the XAN token.
contract DeployXanVesting is Script {
    /// @notice Reads the recipients from a JSON file and deploys `XanVesting` with them.
    /// @param xanToken The XAN token proxy.
    /// @param initialOwner The account that can add more principals and withdraw the surplus.
    /// @param recipientsPath The path of a JSON file in the form `{"recipients": [{"account": "0x…", "principal": "…"}]}`,
    /// with the principals in the smallest unit (18 decimals).
    /// @return vesting The deployed `XanVesting`.
    function run(address xanToken, address initialOwner, string calldata recipientsPath)
        public
        returns (address vesting)
    {
        vesting = deploy({xanToken: xanToken, initialOwner: initialOwner, recipients: readRecipients(recipientsPath)});
    }

    /// @notice Deploys `XanVesting` if no recipient has a principal in the XAN token.
    /// @param xanToken The XAN token proxy.
    /// @param initialOwner The account that can add more principals and withdraw the surplus.
    /// @param recipients The initial accounts and the principals vesting for them.
    /// @return vesting The deployed `XanVesting`.
    function deploy(address xanToken, address initialOwner, IXanVesting.Recipient[] memory recipients)
        public
        returns (address vesting)
    {
        require(xanToken != address(0), XanVesting.ZeroTokenNotAllowed());

        uint256 count = recipients.length;
        for (uint256 i = 0; i < count; ++i) {
            address account = recipients[i].account;
            uint256 tokenPrincipal = IXanV2(xanToken).principalOf(account);
            require(tokenPrincipal == 0, XanVesting.PrincipalSetInToken({account: account, principal: tokenPrincipal}));
        }

        vm.startBroadcast(msg.sender);
        vesting =
            address(new XanVesting({xanToken: IERC20(xanToken), initialOwner: initialOwner, recipients: recipients}));
        vm.stopBroadcast();
    }

    /// @notice Reads the recipients from a JSON file.
    /// @param path The path of the JSON file, in the form that `run` describes.
    /// @return recipients The accounts and the principals vesting for them.
    function readRecipients(string calldata path) public view returns (IXanVesting.Recipient[] memory recipients) {
        // NOTE: The `fs_permissions` of `foundry.toml` allow only reads, and only from the listed folders.
        // forge-lint: disable-next-line(unsafe-cheatcode)
        string memory json = vm.readFile(path);
        recipients = abi.decode(
            vm.parseJsonTypeArray(json, ".recipients", "Recipient(address account,uint256 principal)"),
            (IXanVesting.Recipient[])
        );
    }
}
