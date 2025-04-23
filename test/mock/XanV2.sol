// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import {Xan} from "../../src/Xan.sol";

/// @custom:oz-upgrades-from Xan
contract XanV2 is Xan {
    event Reinitialized();

    function initialize(address initialOwner) external override initializer {
        __Xan_init(initialOwner);
        __XanV2_init();
    }

    /// @custom:oz-upgrades-validate-as-initializer
    function initializeV2() external reinitializer(2) 
    // solhint-disable-next-line no-empty-blocks
    {
        __XanV2_init();
        emit Reinitialized();
    }

    function __XanV2_init() internal onlyInitializing 
    // solhint-disable-next-line no-empty-blocks
    {}
}
