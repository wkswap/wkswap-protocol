// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./WkSwapPool.sol";

contract WkSwapUSDTPool is WkSwapPool, Ownable {
    constructor(
        address token,
        uint256 LTV,
        address _provider
    ) WkSwapPool(token, LTV, _provider) Ownable() {}
}
