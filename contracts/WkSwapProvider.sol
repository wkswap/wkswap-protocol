// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./interfaces/IWkSwapProvider.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract WkSwapProvider is IWkSwapProvider, Ownable {
    mapping(address => address) private _pools;

    address private _extendAddressesProvider;

    address private _rewardPool;

    constructor() Ownable() {}

    function getWkSwapPool(address token) public view override returns (address) {
        return _pools[token];
    }

    function setWkSwapPool(address token, address pool) public override onlyOwner {
        address old = _pools[token];
        _pools[token] = pool;
        emit SetPool(token, old, pool);
    }

    function getRewardPool() public view override returns (address) {
        return _rewardPool;
    }

    function setRewardPool(address rewardPool) public override onlyOwner {
        address old = _rewardPool;
        _rewardPool = rewardPool;
        emit SetRewardPool(old, rewardPool);
    }

    //Not used yet
    function getExtendAddressesProvider() external view override returns (address) {
        return _extendAddressesProvider;
    }

    //Not used yet
    function setExtendAddressesProvider(address extend) public override onlyOwner {
        _extendAddressesProvider = extend;
    }

    event SetPool(address _token, address _old, address _new);

    event SetRewardPool(address _old, address _new);
}
