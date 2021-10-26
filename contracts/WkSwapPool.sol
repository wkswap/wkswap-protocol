// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./utils/LowGasSafeMath.sol";
import "./utils/TransferHelper.sol";
import "./interfaces/IWkSwapProvider.sol";
import "./interfaces/IWkSwapPool.sol";
import "./interfaces/IRewardPool.sol";

contract WkSwapPool is IWkSwapPool {
    // using SafeMath for uint256;
    using LowGasSafeMath for uint256;

    uint256 private constant BASE = 10**18;
    uint256 private constant SECONDS_OF_YEAR = 365 * 24 * 60 * 60;

    IWkSwapProvider public immutable provider;

    //The deposit and borrowing of this contract are all this token
    IERC20 public immutable _token;

    //user => total amount
    mapping(address => uint256) private _deposit;
    mapping(address => uint256) private _borrow;

    //user => Pledge token => borrow this token amount
    mapping(address => mapping(address => uint256)) private _borrowTokenAmount;

    //user => Pledge token => Pledge this token amount
    mapping(address => mapping(address => uint256)) private _pledgeToken;

    //total token
    uint256 private _deposits;
    uint256 private _borrows;

    uint256 private _lastTimestamp;

    //Current interest rate
    uint256 private _depositAnnualInterestRate;
    uint256 private _borrowAnnualInterestRate;

    //Total principal growth rate
    ///@dev 1e18 = 100%, 1.1e18 = 110%
    uint256 private _depositIndexes;
    uint256 private _borrowIndexes;

    //token => Index value on entry
    mapping(address => uint256) private _depositIndex;

    //user  => Pledge token => Index value on entry
    mapping(address => mapping(address => uint256)) private _borrowTokenIndex;

    //The Maximum Loan-to-Value ratio represents the maximum borrowing power of a specific collateral
    //percentage of lending deposit
    ///@dev 1e18 = 100%, 8e17 = 80%
    uint256 private immutable _LTV;

    uint256 public constant _threshold = 5e16;

    uint256 public constant _baseLiquidationRatio = 6e17;

    constructor(
        address token,
        uint256 LTV,
        address _provider
    ) {
        _lastTimestamp = block.timestamp;
        _borrowIndexes = BASE;
        _depositIndexes = BASE;
        _LTV = LTV;
        _token = IERC20(token);
        provider = IWkSwapProvider(_provider);
    }

    function getDeposits() public view override returns (uint256) {
        return _deposits;
    }

    function getDeposit(address user) public view override returns (uint256) {
        return _deposit[user];
    }

    function getBorrows() public view override returns (uint256) {
        return _borrows;
    }

    function getBorrow(address user) public view override returns (uint256) {
        return _borrow[user];
    }

    function getLTV() public view override returns (uint256) {
        return _LTV;
    }

    function getAPR() public view override returns (uint256 depositInterestRate, uint256 borrowInterestRate) {
        return (_depositAnnualInterestRate, _borrowAnnualInterestRate);
    }

    function userTotalDepoist(address user) public view override returns (uint256 userDeposit, uint256 totalDepoist) {
        userDeposit = _deposit[user];

        //Calculate the actual amount of users based on the added index
        totalDepoist = _depositIndexes.sub(_depositIndex[user]).add(BASE).mul(userDeposit).div(BASE);
    }

    function userTotalBorrow(address pledgedToken, address user)
        public
        view
        returns (uint256 userBorrow, uint256 totalBorrow)
    {
        userBorrow = _borrowTokenAmount[user][pledgedToken];
        totalBorrow = _borrowIndexes.sub(_borrowTokenIndex[user][pledgedToken]).add(BASE).mul(userBorrow).div(BASE);
    }

    function getLoanableAmount(address pledgedToken, address user) public view override returns (uint256) {
        require(address(_token) != pledgedToken, "WSP: Cannot lend the same token");

        address pool = _getPool(pledgedToken);
        (, uint256 totalDepoist) = IWkSwapPool(pool).userTotalDepoist(user);
        return totalDepoist.mul(_LTV).div(BASE).sub(_borrowTokenAmount[user][pledgedToken]);
    }

    function getWithdrawableAmount(address pledgedToken, address user) public view override returns (uint256) {
        require(address(_token) != pledgedToken, "WSP: Cannot lend the same token");

        address pool = _getPool(pledgedToken);
        (, uint256 totalDepoist) = IWkSwapPool(pool).userTotalDepoist(user);
        (, uint256 totalBorrow) = userTotalBorrow(pledgedToken, user);
        if (totalBorrow == 0) {
            return totalDepoist;
        } else {
            return totalDepoist.mul(_LTV).div(BASE).sub(totalBorrow);
        }
    }

    //Deposit tokens to the fund pool
    ///@dev dapp first on web check approve amount
    function deposit(address token, uint256 amount) public virtual override {
        updateIndex();

        if (_deposit[msg.sender] > 0) {
            (, uint256 totalDepoist) = userTotalDepoist(msg.sender);
            _depositIndex[msg.sender] = totalDepoist.add(amount);
        } else {
            _deposit[msg.sender] = amount;
        }
        _depositIndex[msg.sender] = _depositIndexes;

        TransferHelper.safeTransferFrom(token, msg.sender, address(this), amount);

        updateInterestRate();
        emit Deposit(msg.sender, token, amount);
    }

    //Withdraw storage tokens
    function withdrawal(address token, uint256 amount) public override {
        //Verify that the fund pool balance is sufficient, Because of loaned tokens
        require(IERC20(token).balanceOf(address(this)) > amount, "POOL: Insufficient fund pool balance");

        uint256 withdrawableAmount = getWithdrawableAmount(token, msg.sender);
        require(withdrawableAmount > amount, "WSP: Can't extract that much");

        (uint256 userDeposit, uint256 totalDepoist) = userTotalDepoist(msg.sender);

        require(totalDepoist >= amount, "POOL: Not so much balance");

        updateIndex();

        //Prevent loss of accuracy
        // (amount / userTotalDepoist) * userDeposit
        uint256 subDeposit = amount.mul(userDeposit).div(totalDepoist);

        //The remaining interest is added to the deposit
        uint256 remainingInterest = totalDepoist.sub(userDeposit).sub(amount.sub(subDeposit));

        _deposit[msg.sender] = _deposit[msg.sender].add(remainingInterest).sub(subDeposit);
        _deposits = _deposits.add(remainingInterest).sub(subDeposit);

        //Then reset the index
        _depositIndex[msg.sender] = _depositIndexes;

        _token.transfer(msg.sender, amount);

        updateInterestRate();
        emit Withdrawal(msg.sender, token, amount);
    }

    /**
     * Lending current token
     * @param pledgedToken Pledged token
     * @param amount Borrow amount
     */
    function borrow(address pledgedToken, uint256 amount) public virtual override {
        uint256 loanableAmount = getLoanableAmount(pledgedToken, msg.sender);
        require(loanableAmount > amount, "WSP: Can't lend that much");

        require(loanableAmount < _deposits.sub(_borrows), "WSP: Insufficient borrowable funds");

        updateIndex();

        if (_borrowTokenAmount[msg.sender][pledgedToken] > 0) {
            (, uint256 totalBorrow) = userTotalBorrow(pledgedToken, msg.sender);
            _borrow[msg.sender] = _borrow[msg.sender].add(amount);
            _borrowTokenAmount[msg.sender][pledgedToken] = totalBorrow.add(amount);
        } else {
            _borrow[msg.sender] = amount;
            _borrowTokenAmount[msg.sender][pledgedToken] = amount;
        }
        _borrowTokenIndex[msg.sender][pledgedToken] = _borrowIndexes;

        _borrows = _borrows.add(amount);

        TransferHelper.safeTransfer(address(_token), msg.sender, amount);

        updateInterestRate();
        emit Borrow(msg.sender, pledgedToken, address(_token), amount);
    }

    /**
     * @dev dapp first on web check approve amount
     * @param all Whether to repay all
     * @param amount If all is true, it can be 0, otherwise it must have a value
     */
    function repay(
        address pledgedToken,
        uint256 amount,
        bool all
    ) public override {
        updateIndex();

        (uint256 userBorrow, uint256 totalBorrow) = userTotalBorrow(pledgedToken, msg.sender);
        require(totalBorrow > 0, "WSP: No need to repay");

        if (all) {
            amount = totalBorrow;
        } else {
            require(amount > 0, "WSP: amount must be > 0");
        }

        uint256 allowanceAmount = _token.allowance(msg.sender, address(this));
        require(allowanceAmount >= amount, "WSP: Insufficient amount of approve");

        if (all) {
            uint256 allBorrow = _borrowTokenAmount[msg.sender][pledgedToken];
            _borrowTokenAmount[msg.sender][pledgedToken] = 0;
            _borrow[msg.sender] = _borrow[msg.sender].sub(allBorrow);
            _borrows = _borrows.sub(allBorrow);
        } else {
            uint256 subBorrow = amount.mul(totalBorrow).div(userBorrow);
            uint256 interest = totalBorrow.sub(userBorrow);

            //borrows interest add to user borrows
            _borrowTokenAmount[msg.sender][pledgedToken] = userBorrow.sub(subBorrow).add(interest);
            _borrow[msg.sender] = _borrow[msg.sender].sub(subBorrow);
            _borrows = _borrows.sub(subBorrow);
        }

        //Reset index
        _borrowTokenIndex[msg.sender][pledgedToken] = _borrowIndexes;

        assert(_token.transferFrom(msg.sender, address(this), amount));

        updateInterestRate();

        emit Repay(msg.sender, pledgedToken, address(_token), amount, all);
    }

    function liquidation(address pledgedToken, address user) public override {
        (
            uint256 liquidationRatio,
            address giveToken,
            ,
            uint256 giveAmount,
            uint256 getAmount,
            ,
            uint256 liquidationFee
        ) = liquidationInfo(pledgedToken, user);

        require(liquidationRatio > 0, "WSP: Unable to liquidate");

        uint256 allowanceAmount = IERC20(giveToken).allowance(msg.sender, address(this));
        require(allowanceAmount >= giveAmount, "WSP: Insufficient amount of approve");

        address pool = _getPool(pledgedToken);
        (, uint256 totalDepoist) = IWkSwapPool(pool).userTotalDepoist(user);
        (, uint256 totalBorrow) = userTotalBorrow(pledgedToken, user);

        TransferHelper.safeTransfer(giveToken, provider.getRewardPool(), liquidationFee);

        if (liquidationRatio >= 9e17) {
            _borrowTokenAmount[user][pledgedToken] = 0;
            _borrow[user] = 0;
        } else {
            _borrow[user] = totalBorrow.sub(getAmount);
            _borrowTokenAmount[user][pledgedToken] = _borrowTokenAmount[user][pledgedToken].sub(getAmount);
        }

        IWkSwapPool(pool).subUserDeposit(user, totalDepoist, getAmount.add(liquidationFee));

        IWkSwapPool(pool).transfer(msg.sender, getAmount);
    }

    ///@return liquidationRatio liquidation Ratio
    ///@return giveToken The liquidator gets token
    ///@return getToken Token given by the liquidator
    function liquidationInfo(address pledgedToken, address user)
        public
        view
        override
        returns (
            uint256 liquidationRatio,
            address giveToken,
            address getToken,
            uint256 giveAmount,
            uint256 getAmount,
            uint256 liquidationAmount,
            uint256 liquidationFee
        )
    {
        require(address(_token) != pledgedToken, "WSP: Cannot lend the same token");

        address pool = _getPool(pledgedToken);
        (, uint256 totalDepoist) = IWkSwapPool(pool).userTotalDepoist(user);
        (, uint256 totalBorrow) = userTotalBorrow(pledgedToken, user);

        uint256 threshold = _LTV.add(_threshold);
        uint256 requiredDeposit = totalBorrow.mul(threshold).div(BASE);
        if (requiredDeposit < totalDepoist) {
            return (0, address(0), address(0), 0, 0, 0, 0);
        }

        ///@dev (Loan-to-deposit ratio - threshold) * 2 + _baseLiquidationRatio
        ///@dev Loan-to-deposit ratio = 85%, liquidationRatio = 60%
        ///@dev Loan-to-deposit ratio = 100%, liquidationRatio = 90%
        liquidationRatio = totalBorrow.mul(BASE).div(totalDepoist).div(BASE).sub(threshold).mul(2).add(
            _baseLiquidationRatio
        );

        liquidationAmount = totalBorrow.mul(liquidationRatio).div(BASE);
        giveToken = address(_token);
        getToken = pledgedToken;
        giveAmount = liquidationAmount.mul(95).div(100);
        liquidationFee = liquidationAmount.div(100);
        getAmount = liquidationAmount.sub(liquidationFee);
    }

    ///@notice Call this function from other fund pools to reduce user pledge
    ///@param totalDepoist user total depoist
    function subUserDeposit(
        address user,
        uint256 totalDepoist,
        uint256 subAmount
    ) public override {
        require(
            _getPool(msg.sender) != address(0) && msg.sender != address(this),
            "WSP: The source of the request is not a fund pool or other fund pool"
        );
        _deposit[user] = totalDepoist.sub(subAmount);
        _deposits = _deposits.sub(subAmount);
        updateIndex();
    }

    function transfer(address to, uint256 amount) public override {
        require(
            _getPool(msg.sender) != address(0) && msg.sender != address(this),
            "WSP: The source of the request is not a fund pool or other fund pool"
        );
        TransferHelper.safeTransfer(address(_token), to, amount);
    }

    function updateInterestRate() private {
        (uint256 depositInterestRate, uint256 borrowInterestRate) = _getAPR();
        _depositAnnualInterestRate = depositInterestRate;
        _borrowAnnualInterestRate = borrowInterestRate;
        emit UpdateInterestRate(depositInterestRate, borrowInterestRate);
    }

    function updateIndex() private {
        (uint256 depositAddedIndex, uint256 borrowAddedIndex) = _getCurrentAddedIndex();

        _depositIndexes = _depositIndexes.add(depositAddedIndex);
        _borrowIndexes = _borrowIndexes.add(borrowAddedIndex);
        emit UpdateIndex(_depositIndexes, _borrowIndexes);
    }

    ///Calculate apy according to deposit loan ratio
    ///@dev The meaning of return value: 1e18 = 100%, 0.9232e18 = 92.32%
    function _getAPR() private view returns (uint256 depositInterestRate, uint256 borrowInterestRate) {
        if (_deposits == 0 || _borrows == 0) {
            return (0, 0);
        }

        uint256 borrowRatio = _borrows.mul(BASE).div(_deposits);

        uint256 r = borrowRatio > BASE ? BASE : borrowRatio;
        uint256 r2 = (r * r) / BASE;
        uint256 r4 = (r2 * r2) / BASE;
        uint256 r8 = (r4 * r4) / BASE;

        borrowInterestRate = ((r2 / 100) + ((4 * r4) / 10) + ((55 * r8) / 100)) / 2;
        depositInterestRate = borrowInterestRate.mul(13).div(20);
    }

    //Get the currently added index
    function _getCurrentAddedIndex() private view returns (uint256 depositAddedIndex, uint256 borrowAddedIndex) {
        uint256 timeDelta = block.timestamp.sub(_lastTimestamp);

        uint256 depositThisTimeGrowthRate = _depositAnnualInterestRate.mul(timeDelta).div(SECONDS_OF_YEAR);

        uint256 borrowThisTimeGrowthRate = _borrowAnnualInterestRate.mul(timeDelta).div(SECONDS_OF_YEAR);

        depositAddedIndex = depositThisTimeGrowthRate.mul(_depositIndexes).div(BASE);
        borrowAddedIndex = borrowThisTimeGrowthRate.mul(_depositIndexes).div(BASE);
    }

    function _getPool(address token) private view returns (address pool) {
        pool = provider.getWkSwapPool(token);
        require(pool != address(0), "WSP: There is no such fund pool");
    }

    event Deposit(address user, address token, uint256 amount);

    event Withdrawal(address user, address token, uint256 amount);

    event Borrow(address user, address pledgeToken, address borrowToken, uint256 amount);

    event Repay(address user, address pledgedToken, address borrowToken, uint256 amount, bool all);

    event UpdateIndex(uint256 depositIndexes, uint256 borrowIndexes);

    event UpdateInterestRate(uint256 depositAnnualInterestRate, uint256 borrowAnnualInterestRate);
}
