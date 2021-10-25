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

    function getLoanableAmount(address, address) external view returns (uint256);

    function deposit(address, uint256) external;

    function withdrawal(address, uint256) external;

    function getWithdrawableAmount(address, address) external view returns (uint256);

    function borrow(address, uint256) external;

    function liquidation(address, address) external;

    function repay(
        address,
        uint256,
        bool
    ) external;

    function liquidationInfo(address, address)
        external
        view
        returns (
            uint256 liquidationRatio,
            address giveToken,
            address getToken,
            uint256 giveAmount,
            uint256 getAmount,
            uint256 liquidationAmount,
            uint256 liquidationFee
        );

    function subUserDeposit(
        address,
        uint256 totalDepoist,
        uint256 subAmount
    ) external;

    function transfer(address to, uint256 amount) external;
}
