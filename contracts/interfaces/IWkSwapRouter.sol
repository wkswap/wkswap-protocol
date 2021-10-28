// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IWkSwapRouter {
    function getAllBorrow(address user, address pledgeToken) external view returns (uint256);

    function addBorrowTokenPool(
        address user,
        address pledgeToken,
        address pool
    ) external;

    function subBorrowTokenPool(
        address user,
        address pledgeToken,
        address pool
    ) external;
}
