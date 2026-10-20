// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";

import {IXanV2Vesting} from "../src/interfaces/IXanV2Vesting.sol";
import {Parameters} from "../src/libs/Parameters.sol";
import {XAN_TOKEN, XAN_V2_VESTING_PROXY} from "./DeployXanV2Vesting.s.sol";

/// @notice Checks the recipients of `RECIPIENTS_PATH` and writes their `addRecipients` call to the `XanV2Vesting` proxy
/// as a batch file of the Safe Transaction Builder for Ethereum mainnet and for Sepolia. A signer of the council
/// multisig imports the file of the chain into the Transaction Builder.
contract GenerateXanV2VestingRecipientsPayload is Script {
    /// @notice The recipients, and the expected sum of their principals, in the smallest unit (18 decimals).
    string public constant RECIPIENTS_PATH = "script/xan-v2-vesting-recipients.json";

    /// @notice The batch file for Ethereum mainnet.
    string public constant MAINNET_PAYLOAD_PATH = "safe-payloads/addRecipients_to_xanV2Vesting_mainnet.json";

    /// @notice The batch file for Sepolia.
    string public constant SEPOLIA_PAYLOAD_PATH = "safe-payloads/addRecipients_to_xanV2Vesting_sepolia.json";

    /// @notice The chain ID of Ethereum mainnet.
    uint256 public constant MAINNET_CHAIN_ID = 1;

    /// @notice The chain ID of Sepolia.
    uint256 public constant SEPOLIA_CHAIN_ID = 11_155_111;

    /// @notice The batch file, in the layout that the Transaction Builder exports.
    /// @dev `createdAt` is fixed, so that the same recipients always give the same file.
    string internal constant _BATCH_FILE = "{\n" "  \"version\": \"1.0\",\n" "  \"chainId\": \"<chainId>\",\n"
        "  \"createdAt\": 0,\n" "  \"meta\": {\n" "    \"name\": \"Add XanV2Vesting recipients\",\n"
        "    \"description\": \"<description>\",\n" "    \"txBuilderVersion\": \"2.1.0\",\n"
        "    \"createdFromSafeAddress\": \"<safe>\",\n" "    \"createdFromOwnerAddress\": \"\",\n"
        "    \"checksum\": \"<checksum>\"\n" "  },\n" "  \"transactions\": [\n" "    {\n" "      \"to\": \"<to>\",\n"
        "      \"value\": \"0\",\n" "      \"data\": \"<data>\",\n" "      \"contractMethod\": null,\n"
        "      \"contractInputsValues\": null\n" "    }\n" "  ]\n" "}\n";

    /// @notice The text of `_BATCH_FILE` that the Transaction Builder hashes into `meta.checksum`.
    /// @dev The serialization of `checksum.ts` in the Safe Transaction Builder: it sorts the keys, sets `meta.name` to
    /// null, and leaves out `meta.checksum`.
    string internal constant _CHECKSUM_INPUT = "{[\"chainId\",\"createdAt\",\"meta\",\"transactions\",\"version\"]"
        "\"<chainId>\",0,"
        "{[\"createdFromOwnerAddress\",\"createdFromSafeAddress\",\"description\",\"name\",\"txBuilderVersion\"]"
        "\"\",\"<safe>\",\"<description>\",null,\"2.1.0\",},"
        "[{[\"contractInputsValues\",\"contractMethod\",\"data\",\"to\",\"value\"]null,null,\"<data>\",\"<to>\",\"0\",}],"
        "\"1.0\",}";

    /// @notice The description of the batch, which contains no character that JSON escapes.
    string internal constant _DESCRIPTION = "Calls addRecipients on XanV2Vesting with the recipients of "
        "script/xan-v2-vesting-recipients.json. Recipient count: <count>. Total principal: <totalPrincipal> (smallest "
        "unit, 18 decimals).";

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

    /// @notice Checks the recipients of `RECIPIENTS_PATH` and writes their batch files to `MAINNET_PAYLOAD_PATH` and
    /// `SEPOLIA_PAYLOAD_PATH`.
    function run() public {
        // NOTE: The `fs_permissions` of `foundry.toml` allow reads only from the listed paths.
        // forge-lint: disable-next-line(unsafe-cheatcode)
        string memory json = vm.readFile(RECIPIENTS_PATH);
        (IXanV2Vesting.Recipient[] memory recipients, uint256 totalPrincipal) = parseRecipients(json);
        check({recipients: recipients, totalPrincipal: totalPrincipal});

        // NOTE: The `fs_permissions` of `foundry.toml` allow writes only to the two batch files.
        // forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeFile({
            path: MAINNET_PAYLOAD_PATH,
            data: batchFile({chainId: MAINNET_CHAIN_ID, recipients: recipients, totalPrincipal: totalPrincipal})
        });
        // forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeFile({
            path: SEPOLIA_PAYLOAD_PATH,
            data: batchFile({chainId: SEPOLIA_CHAIN_ID, recipients: recipients, totalPrincipal: totalPrincipal})
        });
    }

    /// @notice Reads the recipients and the expected sum of their principals from the text of a recipients file.
    /// @param json The text in the form
    /// `{"totalPrincipal": "…", "recipients": [{"account": "0x…", "principal": "…"}]}`, with decimal strings in the
    /// smallest unit (18 decimals).
    /// @return recipients The accounts and the principals vesting for them.
    /// @return totalPrincipal The expected sum of the principals.
    function parseRecipients(string memory json)
        public
        pure
        returns (IXanV2Vesting.Recipient[] memory recipients, uint256 totalPrincipal)
    {
        recipients = abi.decode(
            vm.parseJsonTypeArray(json, ".recipients", "Recipient(address account,uint256 principal)"),
            (IXanV2Vesting.Recipient[])
        );
        totalPrincipal = vm.parseJsonUint(json, ".totalPrincipal");
    }

    /// @notice Returns the Transaction Builder batch file that adds the recipients on a chain.
    /// @param chainId The chain of the council multisig that imports the file.
    /// @param recipients The accounts and the principals vesting for them.
    /// @param totalPrincipal The sum of the principals.
    /// @return json The batch file, with the checksum that the Transaction Builder checks on import.
    function batchFile(uint256 chainId, IXanV2Vesting.Recipient[] memory recipients, uint256 totalPrincipal)
        public
        pure
        returns (string memory json)
    {
        string memory description = vm.replace(_DESCRIPTION, "<count>", vm.toString(recipients.length));
        description = vm.replace(description, "<totalPrincipal>", vm.toString(totalPrincipal));
        bytes memory data = abi.encodeCall(IXanV2Vesting.addRecipients, (recipients));

        string memory checksumInput =
            _fill({template: _CHECKSUM_INPUT, chainId: chainId, description: description, data: data});
        json = _fill({template: _BATCH_FILE, chainId: chainId, description: description, data: data});
        json = vm.replace(json, "<checksum>", vm.toString(keccak256(bytes(checksumInput))));
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

    /// @notice Fills the placeholders that `_BATCH_FILE` and `_CHECKSUM_INPUT` share.
    /// @param template `_BATCH_FILE` or `_CHECKSUM_INPUT`.
    /// @param chainId The chain of the council multisig that imports the file.
    /// @param description The description of the batch.
    /// @param data The `addRecipients` call.
    /// @return filled The template with the values of the batch.
    function _fill(string memory template, uint256 chainId, string memory description, bytes memory data)
        internal
        pure
        returns (string memory filled)
    {
        filled = vm.replace(template, "<chainId>", vm.toString(chainId));
        filled = vm.replace(filled, "<safe>", vm.toString(Parameters.COUNCIL_MULTISIG));
        filled = vm.replace(filled, "<description>", description);
        filled = vm.replace(filled, "<to>", vm.toString(XAN_V2_VESTING_PROXY));
        filled = vm.replace(filled, "<data>", vm.toString(data));
    }
}
