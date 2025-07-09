// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {XanV1} from "../../src/XanV1.sol";

/// @notice This mock makes internal functions of the XanV1 token accessible to external callers.
/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract MockXanV1 is XanV1 {
    function isQuorumAndMinLockedSupplyReached(address impl) external view returns (bool isReached) {
        isReached = _isQuorumAndMinLockedSupplyReached(impl);
    }

    function checkDelayCriterion(uint48 endTime) external view {
        _checkDelayCriterion(endTime);
    }
}
