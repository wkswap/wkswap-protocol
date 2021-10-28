// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./WToken.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract WUsdc is WToken, Ownable {

    constructor () WToken("WsSwap Test USDC", "WUSDC") Ownable(){
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

}