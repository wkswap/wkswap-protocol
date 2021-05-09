// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

abstract contract WkSwapPool {

    uint256 constant BASE = 10 ** 18;

    using SafeMath for uint256;

    mapping(address => uint256) private _deposit;

    uint256 private _deposits;

    mapping(address => uint256) private _borrow;

    uint256 private _borrows;

    ///Calculate apy according to deposit loan ratio
    ///@dev The meaning of return value: 1e18 = 100%, 0.9232e18 = 92.32%
    function getAPR() public pure returns (uint256 deposit, uint256 borrow) {
        if (_deposits == 0) {
            return (0, 0);
        }

        uint256 borrowRatio = _borrows.mul(BASE).div(_deposits);

        uint256 r = borrowRatio > BASE ? BASE : borrowRatio;
        uint256 r2 = r * r / BASE;
        uint256 r4 = r2 * r2 / BASE;
        uint256 r8 = r4 * r4 / BASE;

        borrow = ((r2 / 100) + (4 * r4 / 10) + (55 * r8 / 100)) / 2;
        deposit = borrow.mul(13).div(20);
    }

}
