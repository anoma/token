// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {XanV2} from "../../src/drafts/XanV2.sol";

/// @notice This mock points `XanV2` at a locally deployed V1 implementation, since on mainnet the V1 implementation
/// lives at a fixed address that cannot be reproduced by local CREATE deployments. It also forwards the owner and
/// vesting start to the `XanV2` constructor so tests can exercise the contract both before and after the start.
/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract MockXanV2 is XanV2 {
    address private immutable _V1_IMPLEMENTATION;

    /// @custom:oz-upgrades-unsafe-allow constructor state-variable-immutable
    constructor(address v1Implementation, address owner, uint48 vestingStart, uint48 vestingDuration)
        XanV2(owner, vestingStart, vestingDuration)
    {
        _V1_IMPLEMENTATION = v1Implementation;
    }

    function _implementationV1() internal view override returns (address v1Implementation) {
        v1Implementation = _V1_IMPLEMENTATION;
    }
}
