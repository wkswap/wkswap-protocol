// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./WToken.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract WDai is WToken, Ownable {

    constructor () WToken("WsSwap Test DAI", "WDAI") Ownable(){
    }

}