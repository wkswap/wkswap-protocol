// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IRewardPool {
    function redeem(
        address token,
        address to,
        uint256 amount
    ) external;

    function redeemETH(address to, uint256 amount) external payable;

    function balanceOf(address token) external view returns (uint256);

    function viewCall(address to, bytes memory i) external view returns (bytes memory);

    function writeCall(address to, bytes memory i) external returns (bytes memory);
}
