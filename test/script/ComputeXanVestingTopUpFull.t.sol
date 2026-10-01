// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {ComputeXanVestingTopUpFull} from "../../script/ComputeXanVestingTopUpFull.s.sol";
import {ComputeXanVestingTopUpUntil} from "../../script/ComputeXanVestingTopUpUntil.s.sol";
import {XanVestingFixture} from "../fixtures/XanVestingFixture.sol";

contract ComputeXanVestingTopUpFullTest is XanVestingFixture {
    ComputeXanVestingTopUpFull internal _script;

    function setUp() public override {
        super.setUp();
        _script = new ComputeXanVestingTopUpFull();
    }

    function test_run_covers_every_remaining_unlock() public {
        vm.warp(_vestingMid);
        deal(address(_xan), address(_vesting), _script.run(_vesting));

        vm.warp(_vestingEnd);
        _unlockAll();

        assertEq(_xan.balanceOf(address(_vesting)), 0, "full funding must equal the remaining unlocks");
    }

    function test_run_equals_the_top_up_until_the_vesting_end() public {
        vm.warp(_vestingMid);

        uint256 topUpUntilTheEnd = new ComputeXanVestingTopUpUntil().run({vesting: _vesting, timestamp: _vestingEnd});

        assertEq(_script.run(_vesting), topUpUntilTheEnd);
    }

    function test_run_returns_zero_when_the_contract_is_fully_funded() public {
        deal(address(_xan), address(_vesting), _vesting.totalLockedBalance());

        assertEq(_script.run(_vesting), 0);
    }
}
