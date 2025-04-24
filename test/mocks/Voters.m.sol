// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

contract MockVoters {
    string[16] public names = [
        "Alice",
        "Bob",
        "Carol",
        "Dave",
        "Eve",
        "Frank",
        "Grace",
        "Harold",
        "Ivy",
        "Jack",
        "Kathrine",
        "Luis",
        "Mallory",
        "Nick",
        "Olga",
        "Paul"
    ];

    address[16] public addresses;
    mapping(string name => address voter) public voters;
    mapping(string name => uint256 voterId) public voterIds;

    constructor() {
        for (uint256 i = 0; i < names.length; ++i) {
            addresses[i] = address(uint160(i + 1));
            voters[names[i]] = addresses[i];
            voterIds[names[i]] = i;
        }
    }

    function voter(string memory name) public view returns (address addr) {
        addr = voters[name];
    }

    function voter(uint256 id) public view returns (address addr) {
        addr = addresses[id];
    }

    function voterId(string memory name) public view returns (uint256 id) {
        id = voterIds[name];
    }
}
