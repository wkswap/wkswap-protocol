// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

/**
@title AgicAddressesProvider interface
@notice provides the interface to fetch the Agic address
 */

interface IWkSwapProvider {
    struct PoolInfo {
        address pool;
        address token;
        string name;
    }

    function createPool(address token, uint256 LTV) external;

    function getWkSwapPool(address) external view returns (address);

    function getRewardPool() external view returns (address);

    function setRewardPool(address) external;

    //Not used yet
    function getExtendAddressesProvider() external view returns (address);

    //Not used yet
    function setExtendAddressesProvider(address) external;
}
