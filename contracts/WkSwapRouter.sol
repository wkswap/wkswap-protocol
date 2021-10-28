// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./utils/LowGasSafeMath.sol";
import "./interfaces/IWkSwapRouter.sol";
import "./interfaces/IWkSwapProvider.sol";
import "./interfaces/IWkSwapPool.sol";

contract WkSwapRouter is IWkSwapRouter, Ownable {
    using LowGasSafeMath for uint256;

    IWkSwapProvider public immutable provider;

    //user => Pledge token => borrow token pools
    mapping(address => mapping(address => address[])) private _borrowTokenPools;

    //user => Pledge token => borrow token pool => Index number
    mapping(address => mapping(address => mapping(address => uint256))) private _borrowTokenPoolIndex;

    constructor(address _provider) {
        provider = IWkSwapProvider(_provider);
    }

    function getAllBorrow(address user, address pledgeToken) public view override returns (uint256 totalBorrows) {
        address[] storage pools = _borrowTokenPools[user][pledgeToken];
        for (uint256 i = 0; i < pools.length; i++) {
            if (pools[i] == address(0)) {
                continue;
            }
            (, uint256 totalBorrow) = IWkSwapPool(pools[i]).userTotalBorrow(user, pledgeToken);
            totalBorrows = totalBorrows.add(totalBorrow);
        }
    }

    function addBorrowTokenPool(
        address user,
        address pledgeToken,
        address pool
    ) public override checkPool {
        if (_borrowTokenPoolIndex[user][pledgeToken][pool] != 0) {
            return;
        }
        _borrowTokenPools[user][pledgeToken].push(pool);
        uint256 length = _borrowTokenPools[user][pledgeToken].length;
        _borrowTokenPoolIndex[user][pledgeToken][pool] = length - 1;
    }

    function subBorrowTokenPool(
        address user,
        address pledgeToken,
        address pool
    ) public override {
        uint256 length = _borrowTokenPoolIndex[user][pledgeToken][pool];
        delete _borrowTokenPools[user][pledgeToken][length];
        _borrowTokenPoolIndex[user][pledgeToken][pool] = 0;
    }

    modifier checkPool() {
        require(provider.hasPool(msg.sender), "WSR: The source must be a fund pool");
        _;
    }
}
