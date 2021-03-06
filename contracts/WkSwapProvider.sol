// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./interfaces/IWkSwapProvider.sol";
import "./WkSwapPool.sol";

contract WkSwapProvider is IWkSwapProvider, Ownable {
    mapping(address => address) private _pools;
    mapping(address => bool) private _hasPools;

    address private _extendAddressesProvider;

    address private _rewardPool;

    address private _router;

    PoolInfo[] private _poolInfos;

    constructor() Ownable() {}

    function createPool(address token, uint256 LTV) public override onlyOwner {
        require(token != address(0) && _pools[token] == address(0), "WSP: The fund pool already exists");
        WkSwapPool pool = new WkSwapPool(token, LTV, address(this));
        _pools[token] = address(pool);
        _poolInfos.push(PoolInfo({ pool: address(pool), token: token, name: IERC20Metadata(token).symbol() }));
        _hasPools[address(pool)] = true;
        emit CreatePool(address(pool), token);
    }

    function getWkSwapPool(address token) public view override returns (address) {
        return _pools[token];
    }

    function hasPool(address pool) public view override returns (bool) {
        return _hasPools[pool];
    }

    function getPools() public view override returns (PoolInfo[] memory) {
        return _poolInfos;
    }

    function getRewardPool() public view override returns (address) {
        return _rewardPool;
    }

    function setRewardPool(address rewardPool) public override onlyOwner {
        address old = _rewardPool;
        _rewardPool = rewardPool;
        emit SetRewardPool(old, rewardPool);
    }

    function getRouter() public view override returns (address) {
        return _router;
    }

    function setRouter(address router) public override onlyOwner {
        address old = _router;
        _router = router;
        emit SetRouter(old, router);
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

    event SetRouter(address _old, address _new);

    event CreatePool(address indexed _pool, address _token);
}
