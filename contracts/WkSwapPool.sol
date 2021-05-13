// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./lib/LowGasSafeMath.sol";
import "./lib/TransferHelper.sol";
import "./lib/IERC20.sol";

abstract contract WkSwapPool {
    uint256 private constant BASE = 10**18;
    uint256 private constant SECONDS_OF_YEAR = 365 * 24 * 60 * 60;

    // using SafeMath for uint256;
    using LowGasSafeMath for uint256;

    mapping(address => uint256) private _deposit;

    uint256 private _deposits;

    mapping(address => uint256) private _borrow;

    uint256 private _borrows;

    uint256 private _lastTimestamp;

    //Current interest rate
    uint256 private _borrowAnnualInterestRate;
    uint256 private _depositAnnualInterestRate;

    //Total principal growth rate
    ///@dev 1e18 = 100%, 1.1e18 = 110%
    uint256 private _depositIndexes;
    uint256 private _borrowIndexes;

    //user => Index value on entry
    mapping(address => uint256) private _depositIndex;
    mapping(address => uint256) private _borrowIndex;

    constructor() {
        _lastTimestamp = block.timestamp;
        _borrowIndexes = BASE;
        _depositIndexes = BASE;
    }

    //Deposit tokens to the fund pool
    function deposit(address token, uint256 amount) public {
        (uint256 depositAddedIndex, ) = _getCurrentAddedIndex();

        updateIndex();

        if (_deposit[msg.sender] > 0) {
            _depositIndex[msg.sender] = _depositIndex[msg.sender].sub(
                depositAddedIndex
            );
        } else {
            _depositIndex[msg.sender] = _depositIndexes;
        }

        _deposit[msg.sender] = _deposit[msg.sender].add(amount);

        TransferHelper.safeTransferFrom(
            token,
            msg.sender,
            address(this),
            amount
        );

        updateInterestRate();

        emit Deposit(msg.sender, token, amount);
    }

    //Withdraw storage tokens
    function withdrawal(address token, uint256 amount) public {
        //Verify that the fund pool balance is sufficient, Because of loaned tokens
        require(
            IERC20(token).balanceOf(address(this)) > amount,
            "POOL: Insufficient fund pool balance"
        );

        updateIndex();

        uint256 userDeposit = _deposit[msg.sender];

        //Calculate the actual amount of users based on the added index
        uint256 userTotalDepoist =
            _depositIndexes
                .sub(_depositIndex[msg.sender])
                .add(BASE)
                .mul(userDeposit)
                .div(BASE);

        require(userTotalDepoist >= amount, "POOL: Not so much balance");

        //Prevent loss of accuracy
        // (amount / userTotalDepoist) * userDeposit
        uint256 subDeposit = amount.mul(userDeposit).div(userTotalDepoist);

        //The remaining interest is added to the deposit
        uint256 remainingInterest =
            userTotalDepoist.sub(userDeposit).sub(amount.sub(subDeposit));

        _deposit[msg.sender] = _deposit[msg.sender].sub(subDeposit).add(
            remainingInterest
        );
        _deposits = _deposits.sub(subDeposit).add(remainingInterest);

        //Then reset the index
        _depositIndex[msg.sender] = _depositIndexes;

        updateInterestRate();
        emit Withdrawal(msg.sender, token, amount);
    }

    function updateInterestRate() private {
        (uint256 depositInterestRate, uint256 borrowInterestRate) = _getAPR();
        _depositAnnualInterestRate = depositInterestRate;
        _borrowAnnualInterestRate = borrowInterestRate;
        emit UpdateInterestRate(depositInterestRate, borrowInterestRate);
    }

    function updateIndex() private {
        (uint256 depositAddedIndex, uint256 borrowAddedIndex) =
            _getCurrentAddedIndex();

        _depositIndexes = _depositIndexes.add(depositAddedIndex);
        _borrowIndexes = _borrowIndexes.add(borrowAddedIndex);
        emit UpdateIndex(_depositIndexes, _borrowIndexes);
    }

    ///Calculate apy according to deposit loan ratio
    ///@dev The meaning of return value: 1e18 = 100%, 0.9232e18 = 92.32%
    function _getAPR()
        public
        view
        returns (uint256 depositInterestRate, uint256 borrowInterestRate)
    {
        if (_deposits == 0) {
            return (0, 0);
        }

        uint256 borrowRatio = _borrows.mul(BASE).div(_deposits);

        uint256 r = borrowRatio > BASE ? BASE : borrowRatio;
        uint256 r2 = (r * r) / BASE;
        uint256 r4 = (r2 * r2) / BASE;
        uint256 r8 = (r4 * r4) / BASE;

        borrowInterestRate =
            ((r2 / 100) + ((4 * r4) / 10) + ((55 * r8) / 100)) /
            2;
        depositInterestRate = borrowInterestRate.mul(13).div(20);
    }

    //Get the currently added index
    function _getCurrentAddedIndex()
        private
        view
        returns (uint256 depositAddedIndex, uint256 borrowAddedIndex)
    {
        uint256 timeDelta = block.timestamp.sub(_lastTimestamp);

        uint256 depositThisTimeGrowthRate =
            _depositAnnualInterestRate.mul(timeDelta).div(SECONDS_OF_YEAR);

        uint256 borrowThisTimeGrowthRate =
            _borrowAnnualInterestRate.mul(timeDelta).div(SECONDS_OF_YEAR);

        depositAddedIndex = depositThisTimeGrowthRate.mul(_depositIndexes).div(
            BASE
        );
        borrowAddedIndex = borrowThisTimeGrowthRate.mul(_depositIndexes).div(
            BASE
        );
    }

    event Deposit(address user, address token, uint256 amount);

    event Withdrawal(address user, address token, uint256 amount);

    event UpdateIndex(uint256 depositIndexes, uint256 borrowIndexes);

    event UpdateInterestRate(
        uint256 depositAnnualInterestRate,
        uint256 borrowAnnualInterestRate
    );
}
