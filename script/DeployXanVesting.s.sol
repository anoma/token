// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Script} from "forge-std/Script.sol";

import {IXanVesting} from "../src/interfaces/IXanVesting.sol";
import {XanVesting} from "../src/XanVesting.sol";

/// @notice Deploys `XanVesting` with the recipients of a JSON file.
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
        IXanVesting.Recipient[] memory recipients = readRecipients(recipientsPath);

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
