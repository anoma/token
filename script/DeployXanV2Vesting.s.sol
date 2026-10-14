// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.30;

import {Upgrades, Options} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Script} from "forge-std/Script.sol";

import {Parameters} from "../src/libs/Parameters.sol";
import {XanV2Vesting} from "../src/XanV2Vesting.sol";

/// @dev The `XanV2Vesting` proxy on Ethereum mainnet and Sepolia. The two chains share the addresses of the token and
/// the governance stack, and they must share those of `XanV2Vesting` too. The deployer of the governance stack,
/// `0xc461247a7375cF7c70a576d636aA3dd38ff3bb2f`, is at the same nonce on both. It creates the implementation at nonce
/// 11, at `0xA4b1B4032c30Ba42a44c3616D3AB95d10170De55`, and the proxy at nonce 12. A CREATE address depends only on
/// the deployer and its nonce, so this one address pins both, and with them the address of the implementation.
address constant XAN_V2_VESTING_PROXY = 0x60A149fE74D2f55219f1Abad2911756Da9c67bf4;

/// @notice Deploys `XanV2Vesting` behind a UUPS proxy without recipients.
contract DeployXanV2Vesting is Script {
    /// @notice The XAN token proxy, which has the same address on Ethereum mainnet and Sepolia.
    address public constant XAN_TOKEN = 0xCEDbEA37C8872c4171259Cdfd5255CB8923Cf8e7;

    /// @notice Thrown if the deployer would not create the proxy at `XAN_V2_VESTING_PROXY`.
    error UnexpectedProxyAddress(address expected, address predicted);

    /// @notice Deploys `XanV2Vesting` from the sender.
    /// @return proxy The `XanV2Vesting` proxy.
    /// @return implementation The `XanV2Vesting` implementation.
    function run() public returns (address proxy, address implementation) {
        (proxy, implementation) = deploy({deployer: msg.sender});
    }

    /// @notice Deploys the `XanV2Vesting` implementation for `XAN_TOKEN` and its proxy from `deployer`, and initializes
    /// the proxy with the council multisig as the owner.
    /// @param deployer The account that broadcasts the deployment.
    /// @return proxy The `XanV2Vesting` proxy.
    /// @return implementation The `XanV2Vesting` implementation.
    function deploy(address deployer) public returns (address proxy, address implementation) {
        // The implementation takes the current nonce of the deployer and the proxy the next one. Revert before anything
        // is broadcast if another account or another nonce would deploy them, because their addresses would then
        // differ between Ethereum mainnet and Sepolia.
        address predictedProxy = vm.computeCreateAddress(deployer, vm.getNonce(deployer) + 1);
        require(
            predictedProxy == XAN_V2_VESTING_PROXY,
            UnexpectedProxyAddress({expected: XAN_V2_VESTING_PROXY, predicted: predictedProxy})
        );

        Options memory opts;
        opts.constructorData = abi.encode(XAN_TOKEN);

        vm.startBroadcast(deployer);
        proxy = Upgrades.deployUUPSProxy({
            contractName: "XanV2Vesting.sol:XanV2Vesting",
            initializerData: abi.encodeCall(XanV2Vesting.initialize, (Parameters.COUNCIL_MULTISIG)),
            opts: opts
        });
        vm.stopBroadcast();

        implementation = Upgrades.getImplementationAddress(proxy);
    }
}
