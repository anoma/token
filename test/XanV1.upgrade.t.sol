// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {Upgrades, UnsafeUpgrades, Options} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Test} from "forge-std/Test.sol";

import {XanV2} from "../src/drafts/XanV2.sol";
import {Parameters} from "../src/libs/Parameters.sol";
import {XanV1} from "../src/XanV1.sol";

contract XanV1UpgradeTest is Test {
    using UnsafeUpgrades for address;
    using ERC1967Utils for address;

    address internal _defaultSender;
    address internal _governanceCouncil;
    address internal _newImpl;
    XanV1 internal _xanProxy;

    function setUp() public {
        (, _defaultSender,) = vm.readCallers();

        // Deploy proxy and mint tokens for the `_defaultSender`.
        vm.startPrank(_defaultSender);
        _xanProxy = XanV1(
            Upgrades.deployUUPSProxy({
                contractName: "XanV1.sol:XanV1",
                initializerData: abi.encodeCall(XanV1.initializeV1, (_defaultSender, _governanceCouncil))
            })
        );

        Options memory opts;
        _newImpl = Upgrades.prepareUpgrade({contractName: "XanV2.sol:XanV2", opts: opts});

        // Lock the tokens for the `_defaultSender`.
        _xanProxy.lock(_xanProxy.unlockedBalanceOf(_defaultSender));

        vm.stopPrank();
    }

    function test_upgradeToAndCall_emits_the_Upgraded_event() public {
        //! TODO use gov council for testing

        vm.prank(_defaultSender);
        _xanProxy.castVote(_newImpl);
        _xanProxy.startVoterBodyUpgradeDelay(_newImpl);

        skip(Parameters.DELAY_DURATION);

        vm.expectEmit(address(_xanProxy));
        emit IERC1967.Upgraded(_newImpl);

        address(_xanProxy).upgradeProxy({
            newImpl: _newImpl,
            data: abi.encodeCall(XanV2.reinitializeFromV1, (address(uint160(1))))
        });
    }

    function test_upgradeToAndCall_resets_the_governance_council_address() public {
        //! TODO use gov council for testing

        vm.prank(_defaultSender);
        _xanProxy.castVote(_newImpl);
        _xanProxy.startVoterBodyUpgradeDelay(_newImpl);

        skip(Parameters.DELAY_DURATION);

        vm.expectEmit(address(_xanProxy));
        emit IERC1967.Upgraded(_newImpl);

        address(_xanProxy).upgradeProxy({
            newImpl: _newImpl,
            data: abi.encodeCall(XanV2.reinitializeFromV1, (address(uint160(1))))
        });

        // TODO! ASK CHRIS: Is this desired?
        assertEq(_xanProxy.governanceCouncil(), address(0));
    }

    function test_upgradeToAndCall_allows_upgrade_to_the_same_implementation() public {
        //! TODO use gov council for testing
        address sameImpl = _xanProxy.implementation();

        vm.prank(_defaultSender);
        _xanProxy.castVote(sameImpl);
        _xanProxy.startVoterBodyUpgradeDelay(sameImpl);

        skip(Parameters.DELAY_DURATION);

        vm.expectEmit(address(_xanProxy));
        emit IERC1967.Upgraded(sameImpl);
        address(_xanProxy).upgradeProxy({newImpl: sameImpl, data: ""});
    }
}
