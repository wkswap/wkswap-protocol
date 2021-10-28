// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./WToken.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract WUsdt is WToken, Ownable {

    constructor () WToken("WsSwap Test USDT", "WUSDT") Ownable(){
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

}