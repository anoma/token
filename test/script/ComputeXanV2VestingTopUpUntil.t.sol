// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

import {ComputeXanV2VestingTopUpUntil} from "../../script/ComputeXanV2VestingTopUpUntil.s.sol";
import {XanV2Vesting} from "../../src/XanV2Vesting.sol";
import {XanV2VestingFixture} from "../fixtures/XanV2VestingFixture.sol";

contract ComputeXanV2VestingTopUpUntilTest is XanV2VestingFixture {
    ComputeXanV2VestingTopUpUntil internal _script;

    function setUp() public override {
        super.setUp();
        _script = new ComputeXanV2VestingTopUpUntil();
    }

    function testFuzz_run_covers_every_unlock_until_the_timestamp(uint256 topUpTime, uint256 untilTime) public {
        topUpTime = bound(topUpTime, _vestingStart, _vestingEnd);
        untilTime = bound(untilTime, topUpTime, _vestingEnd + 365 days);

        vm.warp(topUpTime);
        deal(address(_xan), address(_vesting), _script.run({vesting: _vesting, timestamp: uint48(untilTime)}));

        vm.warp(untilTime);
        _unlockAll();
    }

    function test_run_computes_the_top_up_of_the_pinned_proxy() public {
        XanV2Vesting vesting = _deployPinnedVesting();

        assertEq(_script.run(_vestingEnd), vesting.totalPrincipal(), "an unfunded proxy needs every principal");
    }

    function test_run_returns_exactly_the_unlock_of_a_single_recipient() public {
        XanV2Vesting vesting = _deployVesting(_recipients(_ALICE, _PRINCIPAL));

        uint48 topUpTime = _vestingStart + 101;
        uint48 untilTime = topUpTime + 30 days;

        vm.warp(topUpTime);
        uint256 topUp = _script.run({vesting: vesting, timestamp: untilTime});
        deal(address(_xan), address(vesting), topUp);

        vm.warp(untilTime);
        vm.prank(_ALICE);
        assertEq(vesting.unlock(), topUp, "a single recipient must unlock exactly the top-up");
    }

    function test_run_restores_the_block_timestamp() public {
        vm.warp(_vestingMid);

        _script.run({vesting: _vesting, timestamp: _vestingEnd});

        assertEq(Time.timestamp(), _vestingMid);
    }

    function test_run_returns_zero_when_the_balance_is_enough() public {
        deal(address(_xan), address(_vesting), _vesting.totalLockedBalance());
        vm.warp(_vestingMid);

        assertEq(_script.run({vesting: _vesting, timestamp: _vestingEnd}), 0);
    }

    function test_run_reverts_on_a_timestamp_in_the_past() public {
        vm.warp(_vestingMid);
        uint48 timestamp = _vestingMid - 1;

        vm.expectRevert(
            abi.encodeWithSelector(ComputeXanV2VestingTopUpUntil.TimestampInThePast.selector, timestamp, _vestingMid)
        );
        _script.run({vesting: _vesting, timestamp: timestamp});
    }
}
