// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";

import {IXanV2Vesting} from "../src/interfaces/IXanV2Vesting.sol";
import {Parameters} from "../src/libs/Parameters.sol";
import {XAN_TOKEN, XAN_V2_VESTING_PROXY} from "./DeployXanV2Vesting.s.sol";

/// @notice Checks the recipients of `RECIPIENTS_PATH` and writes their `addRecipients` call to the `XanV2Vesting` proxy
/// to `PAYLOAD_PATH`, from which a signer of the council multisig creates the Safe transaction by hand.
contract GenerateXanV2VestingRecipientsPayload is Script {
    /// @notice The recipients, and the expected sum of their principals, in the smallest unit (18 decimals).
    string public constant RECIPIENTS_PATH = "script/xan-v2-vesting-recipients.json";

    /// @notice The Safe transaction that adds the recipients.
    string public constant PAYLOAD_PATH = "safe-payloads/addRecipients_to_xanV2Vesting.json";

    /// @notice Thrown if the recipient at `index` is the zero address.
    error ZeroAccountNotAllowed(uint256 index);

    /// @notice Thrown if the recipient at `index` is the `XanV2Vesting` proxy, which cannot call `unlock()`.
    error ProxyRecipientNotAllowed(uint256 index);

    /// @notice Thrown if the recipient at `index` is the XAN token, which cannot call `unlock()`.
    error TokenRecipientNotAllowed(uint256 index);

    /// @notice Thrown if the principal at `index` is zero.
    error ZeroPrincipalNotAllowed(uint256 index);

    /// @notice Thrown if the recipient at `index` occurs earlier in the list.
    error RecipientListedTwice(uint256 index, address account);

    /// @notice Thrown if the principals do not add up to the expected total principal.
    error TotalPrincipalMismatch(uint256 expected, uint256 actual);

    /// @notice Checks the recipients of `RECIPIENTS_PATH` and writes their `addRecipients` call to `PAYLOAD_PATH`.
    function run() public {
        (IXanV2Vesting.Recipient[] memory recipients, uint256 totalPrincipal) = readRecipients(RECIPIENTS_PATH);
        check({recipients: recipients, totalPrincipal: totalPrincipal});

        // NOTE: The `fs_permissions` of `foundry.toml` allow writes only to `PAYLOAD_PATH`.
        // forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeJson({json: payload({recipients: recipients, totalPrincipal: totalPrincipal}), path: PAYLOAD_PATH});
        // The file ends with a newline, so that an editor that adds one on save does not change it.
        // forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeLine({path: PAYLOAD_PATH, data: ""});
    }

    /// @notice Returns the Safe transaction that adds the recipients, as JSON.
    /// @param recipients The accounts and the principals vesting for them.
    /// @param totalPrincipal The sum of the principals.
    /// @return json The transaction, with an instruction for the signer and the numbers to check before signing.
    function payload(IXanV2Vesting.Recipient[] memory recipients, uint256 totalPrincipal)
        public
        returns (string memory json)
    {
        string memory key = "payload";
        vm.serializeString(key, "_instruction", instruction());
        vm.serializeAddress(key, "to", XAN_V2_VESTING_PROXY);
        vm.serializeString(key, "value", "0");
        vm.serializeUint(key, "recipientCount", recipients.length);
        vm.serializeString(key, "totalPrincipal", vm.toString(totalPrincipal));
        json = vm.serializeBytes(key, "data", abi.encodeCall(IXanV2Vesting.addRecipients, (recipients)));
    }

    /// @notice Reads the recipients and the expected sum of their principals from a JSON file.
    /// @param path A JSON file in the form
    /// `{"totalPrincipal": "…", "recipients": [{"account": "0x…", "principal": "…"}]}`, with decimal strings in the
    /// smallest unit (18 decimals).
    /// @return recipients The accounts and the principals vesting for them.
    /// @return totalPrincipal The expected sum of the principals.
    function readRecipients(string memory path)
        public
        view
        returns (IXanV2Vesting.Recipient[] memory recipients, uint256 totalPrincipal)
    {
        // NOTE: The `fs_permissions` of `foundry.toml` allow reads only from the listed paths.
        // forge-lint: disable-next-line(unsafe-cheatcode)
        string memory json = vm.readFile(path);
        recipients = abi.decode(
            vm.parseJsonTypeArray(json, ".recipients", "Recipient(address account,uint256 principal)"),
            (IXanV2Vesting.Recipient[])
        );
        totalPrincipal = vm.parseJsonUint(json, ".totalPrincipal");
    }

    /// @notice Reverts on an entry that `addRecipients` rejects and on principals that do not add up to
    /// `totalPrincipal`.
    /// @dev It cannot read the proxy, so it does not detect an account that already has a principal there.
    /// @param recipients The accounts and the principals vesting for them.
    /// @param totalPrincipal The expected sum of the principals.
    function check(IXanV2Vesting.Recipient[] memory recipients, uint256 totalPrincipal) public pure {
        uint256 count = recipients.length;
        uint256 sum = 0;
        for (uint256 i = 0; i < count; ++i) {
            address account = recipients[i].account;
            require(account != address(0), ZeroAccountNotAllowed(i));
            require(account != XAN_V2_VESTING_PROXY, ProxyRecipientNotAllowed(i));
            require(account != XAN_TOKEN, TokenRecipientNotAllowed(i));
            require(recipients[i].principal != 0, ZeroPrincipalNotAllowed(i));
            for (uint256 j = 0; j < i; ++j) {
                require(recipients[j].account != account, RecipientListedTwice({index: i, account: account}));
            }
            sum += recipients[i].principal;
        }

        require(sum == totalPrincipal, TotalPrincipalMismatch({expected: totalPrincipal, actual: sum}));
    }

    /// @notice Returns what a signer of the council multisig does with the payload.
    /// @return text The instruction.
    function instruction() public pure returns (string memory text) {
        text = string.concat(
            "Create this transaction from the council multisig ",
            vm.toString(Parameters.COUNCIL_MULTISIG),
            ", on Sepolia first and then on Ethereum mainnet. In the Safe app, open the Transaction Builder, turn on "
            "custom data, and enter to, value, and data. Before you sign, check that recipientCount and totalPrincipal "
            "match the reviewed script/xan-v2-vesting-recipients.json."
        );
    }
}
