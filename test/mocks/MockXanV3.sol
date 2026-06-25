// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {MockXanV2} from "./MockXanV2.sol";

/// @notice A stand-in "next version" of the XAN token used to demonstrate that the governor DAO can upgrade the
/// `XanV2` token itself. It adds a `version()` getter so a successful upgrade is observable on-chain.
/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract MockXanV3 is MockXanV2 {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address v1Implementation, address initialOwner, uint48 vestingStart, uint48 vestingDuration)
        MockXanV2(v1Implementation, initialOwner, vestingStart, vestingDuration)
    {}

    /// @notice Returns the implementation version, demonstrating that new logic is reachable after the upgrade.
    function version() external pure returns (uint256 implementationVersion) {
        implementationVersion = 3;
    }
}
