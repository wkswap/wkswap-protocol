// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/IRewardPool.sol";

contract RewardPool is Ownable, IRewardPool {
    constructor() Ownable() {}

    function redeem(
        address token,
        address to,
        uint256 amount
    ) public override onlyOwner {
        IERC20(token).transfer(to, amount);
        emit Redeem(token, to, amount);
    }

    function redeemETH(address to, uint256 amount) public payable override onlyOwner {
        payable(to).transfer(amount);
        emit RedeemETH(to, amount);
    }

    function balanceOf(address token) public view override returns (uint256) {
        if (token == address(0)) {
            return address(this).balance;
        } else {
            return IERC20(token).balanceOf(address(this));
        }
    }

    function viewCall(address to, bytes memory i) public view override onlyOwner returns (bytes memory) {
        (bool success, bytes memory data) = to.staticcall(i);
        require(success);
        return data;
    }

    function writeCall(address to, bytes memory i) public override onlyOwner returns (bytes memory) {
        (bool success, bytes memory data) = to.call(i);
        require(success);
        emit WriteCall(data);
        return data;
    }

    event WriteCall(bytes data);

    event Redeem(address token, address to, uint256 amount);

    event RedeemETH(address to, uint256 amount);

    receive() external payable {}
}
