// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./interfaces/IWkSwapProvider.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract WkSwapProvider is IWkSwapProvider, Ownable {
    mapping(address => uint256) private _whiteListIndex;

    address[] private _whiteList;

    mapping(address => address) private _pools;

    address private _extendAddressesProvider;

    constructor() Ownable() {
        _whiteList.push();
    }

    function getStatisticsWhiteList()
        public
        view
        override
        returns (address[] memory)
    {
        return _whiteList;
    }

    function verifyStatisticsWhiteList(address _address)
        public
        view
        override
        returns (bool)
    {
        return _whiteListIndex[_address] != 0;
    }

    function addStatisticsWhiteList(address _address)
        external
        override
        onlyOwner
    {
        require(_whiteListIndex[_address] == 0, "Address already exists");
        _whiteListIndex[_address] = _whiteList.length;
        _whiteList.push(_address);
        emit AddWhiteListAddress(_address);
    }

    function subStatisticsWhiteList(address _address)
        external
        override
        onlyOwner
    {
        uint256 index = _whiteListIndex[_address];
        require(index != 0, "WhiteList not have this address");
        delete _whiteList[index];
        delete _whiteListIndex[_address];
        emit SubWhiteListAddress(_address);
    }

    function getWkSwapPool(address token)
        public
        view
        override
        returns (address)
    {
        return _pools[token];
    }

    function setWkSwapPool(address token, address pool)
        public
        override
        onlyOwner
    {
        address old = _pools[token];
        _pools[token] = pool;
        emit SetPool(token, old, pool);
    }

    //Not used yet
    function getExtendAddressesProvider()
        external
        view
        override
        returns (address)
    {
        return _extendAddressesProvider;
    }

    //Not used yet
    function setExtendAddressesProvider(address extend)
        public
        override
        onlyOwner
    {
        _extendAddressesProvider = extend;
    }

    event AddWhiteListAddress(address _address);

    event SubWhiteListAddress(address _address);

    event SetPool(address _token, address _old, address _new);
}
