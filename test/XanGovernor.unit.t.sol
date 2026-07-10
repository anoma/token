// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {Test} from "forge-std/Test.sol";

import {DeployGovernance} from "../script/DeployGovernance.s.sol";
import {XanGovernor} from "../src/XanGovernor.sol";
import {XanV1} from "../src/XanV1.sol";

/// @notice Unit tests for `XanGovernor`'s EIP-6372 clock override, checked against a clockless XanV1 token.
contract XanGovernorUnitTest is Test {
    XanGovernor internal _governor;

    function setUp() public {
        DeployGovernance script = new DeployGovernance();
        (address governor,,) = script.deploy({
            token: address(new XanV1()), councilMultisig: makeAddr("councilMultisig"), deployer: address(script)
        });
        _governor = XanGovernor(payable(governor));
    }

    function test_clock_returns_the_timestamp() public view {
        assertEq(_governor.clock(), Time.timestamp());
    }

    function test_CLOCK_MODE_is_timestamp() public view {
        assertEq(_governor.CLOCK_MODE(), "mode=timestamp");
    }
}
