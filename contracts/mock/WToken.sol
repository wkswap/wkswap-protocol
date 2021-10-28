// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

abstract contract WToken is ERC20 {
    mapping(address => bool) private _beenSend;

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint() public {
        require(!_beenSend[msg.sender], "WsSwap Faucet: The address been send");
        _beenSend[msg.sender] = true;
        _mint(msg.sender, 10**decimals() * 100);
    }

    function getBeenSend(address owner) public view returns (bool beenSend) {
        beenSend = _beenSend[owner];
    }
}
