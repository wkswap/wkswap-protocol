// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/erc20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract WkSwapToken is ERC20, Ownable {
    constructor() ERC20("WkSwap Deposit Token", "wToken") Ownable() {}
}
