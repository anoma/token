// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {XanV2} from "../../src/XanV2.sol";

/// @notice This mock makes internal functions of the XanV2 token accessible to external callers.
/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract MockXanV2 is XanV2 {
    address private immutable _V1_IMPLEMENTATION;

    /// @custom:oz-upgrades-unsafe-allow constructor state-variable-immutable
    constructor(address v1Implementation, address owner, uint48 vestingStart, uint48 vestingDuration)
        XanV2(owner, vestingStart, vestingDuration)
    {
        _V1_IMPLEMENTATION = v1Implementation;
    }

    /// @notice Exposes `_transferVotingUnits` so a test can pre-seed the voting total-supply checkpoint from the zero
    /// address — exactly as `reinitializeFromV1` does — before the reinitializer runs.
    /// @param amount The amount to add to the voting total-supply checkpoint.
    function addVotingTotalSupply(uint256 amount) external {
        _transferVotingUnits({from: address(0), to: address(this), amount: amount});
    }

    function _implementationV1() internal view override returns (address v1Implementation) {
        v1Implementation = _V1_IMPLEMENTATION;
    }
}
