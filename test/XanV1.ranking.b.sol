// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Test, console} from "forge-std/Test.sol";

import {XanV1} from "../src/XanV1.sol";

import {MockPersons} from "./mocks/Persons.m.sol";

contract XanV1VotingTest is Test, MockPersons {
    address internal constant _COUNCIL = address(uint160(1));
    address internal _defaultSender;
    XanV1 internal _xanProxy;

    function setUp() public {
        (, _defaultSender,) = vm.readCallers();

        _xanProxy = XanV1(
            Upgrades.deployUUPSProxy({
                contractName: "XanV1.sol:XanV1",
                initializerData: abi.encodeCall(XanV1.initializeV1, (_defaultSender, _COUNCIL))
            })
        );
    }

    function test_castVote_gas_benchmark() public {
        uint256 n = 20890;

        uint256 gasLimit = 36 * 10 ** 6;
        vm.startPrank(_defaultSender);

        _xanProxy.lock(1);
        for (uint256 i = 0; i < n; ++i) {
            _xanProxy.castVote(address(uint160(i + 1)));
        }

        _xanProxy.lock(1);

        uint256 gasBefore = gasleft();
        _xanProxy.castVote(address(uint160(n)));
        uint256 delta = gasBefore - gasleft();

        console.log(delta, gasLimit, gasLimit - delta);
    }

    /*
     * Cost of attack is O(1) while the cost to propose an implementation with the intention to upgrade is O(n).
     * Mitigation: Limit the number of proposed implementations to 256.
     */
}
