p
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract WkSwapUSDTPool is Ownable {

    using SafeMath for uint256;

    mapping(address => uint256) private _deposit;

    uint256 private _deposits;

    mapping(address => uint256) private _borrow;

    uint256 private _borrows;

    constructor() Ownable(){}

    ///Calculate apy according to deposit loan ratio
    ///@dev The meaning of return value: 1000 = 10%, 817 = 8.17%
    function getAPY() public view returns (uint256 deposit, uint256 borrow){
        if (_deposits == 0) {
            return (0, 0);
        }
        uint256 depositRatio = _borrows.mul1e4).div(_deposits);

        if (depositRatio > 9e3)
            deposit = depositRatio.mul(15).div(100);
        if (depositRatio > 8e3)
            deposit = depositRatio.div(10);
        if (depositRatio > 7e3) {
            deposit = depositRatio.div(20);
        } else {
            deposit = depositRatio.div(100);
        }

        borrow = deposit.mul(135).div(100);
    }


}