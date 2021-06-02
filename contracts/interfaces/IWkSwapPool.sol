// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IWkSwapPool {
    function getAPR() external view returns (uint256, uint256);

    function userTotalDepoist(address) external view returns (uint256, uint256);

    function getDeposits() external view returns (uint256);

    function getDeposit(address) external view returns (uint256);

    function getBorrows() external view returns (uint256);

    function getBorrow(address) external view returns (uint256);

    function getLTV() external view returns (uint256);

    function getLoanableAmount(address, address)
        external
        view
        returns (uint256);

    function deposit(address, uint256) external;

    function withdrawal(address, uint256) external;

    function borrow(address, uint256) external;

    function liquidationInfo(address, address)
        external
        view
        returns (
            address giveToken,
            address getToken,
            uint256 giveAmount,
            uint256 getAmount
        );
}
