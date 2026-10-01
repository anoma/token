// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.30;

import {Upgrades, Options} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Script} from "forge-std/Script.sol";

import {IXanV2Vesting} from "../src/interfaces/IXanV2Vesting.sol";
import {Parameters} from "../src/libs/Parameters.sol";
import {XanV2Vesting} from "../src/XanV2Vesting.sol";

/// @notice Deploys `XanV2Vesting` behind a UUPS proxy with the recipients of a JSON file.
contract DeployXanV2Vesting is Script {
    /// @notice The address at which the proxy must land on Ethereum mainnet and Sepolia.
    /// @dev The two chains share the addresses of the token and the governance stack, and they must share those of
    /// `XanV2Vesting` too. The deployer of the governance stack, `0xc461247a7375cF7c70a576d636aA3dd38ff3bb2f`, is at
    /// the same nonce on both. It creates the implementation at nonce 11, at
    /// `0xA4b1B4032c30Ba42a44c3616D3AB95d10170De55`, and the proxy at nonce 12. A CREATE address depends only on the
    /// deployer and its nonce, so this one address pins both, and with them the address of the implementation.
    address public constant EXPECTED_PROXY = 0x60A149fE74D2f55219f1Abad2911756Da9c67bf4;

    uint256 internal constant _MAINNET_CHAIN_ID = 1;
    uint256 internal constant _SEPOLIA_CHAIN_ID = 11_155_111;

    /// @notice Thrown if the proxy would not land at `EXPECTED_PROXY`.
    error UnexpectedProxyAddress(address expected, address predicted);

    /// @notice Reads the recipients from a JSON file, deploys the `XanV2Vesting` implementation and its proxy, and
    /// initializes the proxy with the council multisig as the owner and with the recipients.
    /// @param xanToken The XAN token proxy.
    /// @param recipientsPath The path of a JSON file in the form `{"recipients": [{"account": "0x…", "principal": "…"}]}`,
    /// with the principals in the smallest unit (18 decimals).
    /// @return proxy The `XanV2Vesting` proxy.
    /// @return implementation The `XanV2Vesting` implementation.
    function run(address xanToken, string calldata recipientsPath)
        public
        returns (address proxy, address implementation)
    {
        // On Ethereum mainnet and Sepolia, revert before anything is broadcast if another account or another nonce
        // would deploy the contracts, because their addresses would then differ between the two chains. Other chains,
        // such as a local one, take any deployer.
        if (block.chainid == _MAINNET_CHAIN_ID || block.chainid == _SEPOLIA_CHAIN_ID) {
            requireExpectedProxy(msg.sender);
        }

        IXanV2Vesting.Recipient[] memory recipients = readRecipients(recipientsPath);

        Options memory opts;
        opts.constructorData = abi.encode(xanToken);

        vm.startBroadcast(msg.sender);
        proxy = Upgrades.deployUUPSProxy({
            contractName: "XanV2Vesting.sol:XanV2Vesting",
            initializerData: abi.encodeCall(XanV2Vesting.initialize, (Parameters.COUNCIL_MULTISIG, recipients)),
            opts: opts
        });
        vm.stopBroadcast();

        implementation = Upgrades.getImplementationAddress(proxy);
    }

    /// @notice Reverts unless `deployer` creates the proxy at `EXPECTED_PROXY`.
    /// @dev The implementation takes the current nonce of the deployer and the proxy the next one.
    /// @param deployer The account that broadcasts the deployment.
    function requireExpectedProxy(address deployer) public view {
        address predictedProxy = vm.computeCreateAddress(deployer, vm.getNonce(deployer) + 1);
        require(
            predictedProxy == EXPECTED_PROXY,
            UnexpectedProxyAddress({expected: EXPECTED_PROXY, predicted: predictedProxy})
        );
    }

    /// @notice Reads the recipients from a JSON file.
    /// @param path The path of the JSON file, in the form that `run` describes.
    /// @return recipients The accounts and the principals vesting for them.
    function readRecipients(string calldata path) public view returns (IXanV2Vesting.Recipient[] memory recipients) {
        // NOTE: The `fs_permissions` of `foundry.toml` allow only reads, and only from the listed folders.
        // forge-lint: disable-next-line(unsafe-cheatcode)
        string memory json = vm.readFile(path);
        recipients = abi.decode(
            vm.parseJsonTypeArray(json, ".recipients", "Recipient(address account,uint256 principal)"),
            (IXanV2Vesting.Recipient[])
        );
    }
}
