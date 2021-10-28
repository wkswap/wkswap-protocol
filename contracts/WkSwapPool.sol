// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./utils/LowGasSafeMath.sol";
import "./utils/TransferHelper.sol";
import "./interfaces/IWkSwapProvider.sol";
import "./interfaces/IWkSwapPool.sol";
import "./interfaces/IRewardPool.sol";
import "./interfaces/IWkSwapRouter.sol";

contract WkSwapPool is IWkSwapPool {
    // using SafeMath for uint256;
    using LowGasSafeMath for uint256;

    uint256 private constant BASE = 10**18;
    uint256 private constant SECONDS_OF_YEAR = 365 * 24 * 60 * 60;

    //The Maximum Loan-to-Value ratio represents the maximum borrowing power of a specific collateral
    //percentage of lending deposit
    ///@dev 1e18 = 100%, 8e17 = 80%
    uint256 private immutable _LTV;

    uint256 public constant _threshold = 5e16;

    uint256 public constant _baseLiquidationRatio = 6e17;

    IWkSwapProvider public immutable _provider;

    //The deposit and borrowing of this contract are all this token
    address public immutable _token;

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

    //user => total amount
    mapping(address => uint256) private _deposit;
    mapping(address => uint256) private _borrow;

    //user => Pledge token => borrow this token amount
    mapping(address => mapping(address => uint256)) private _borrowTokenAmount;

    //token => Index value on entry
    mapping(address => uint256) private _depositIndex;

    //user  => Pledge token => Index value on entry
    mapping(address => mapping(address => uint256)) private _borrowTokenIndex;

    //user => Pledge tokens
    mapping(address => address[]) private _borrowByPledge;

    mapping(address => mapping(address => uint256)) private _borrowByPledgeIndex;

    constructor(
        address token,
        uint256 LTV,
        address provider
    ) {
        _lastTimestamp = block.timestamp;
        _borrowIndexes = BASE;
        _depositIndexes = BASE;
        _LTV = LTV;
        _token = token;
        _provider = IWkSwapProvider(provider);
    }

    //Deposit tokens to the fund pool
    ///@dev dapp first on web check approve amount
    function deposit(uint256 amount) public override {
        require(IERC20(_token).allowance(msg.sender, address(this)) >= amount, "WSP: Insufficient allowance amount");
        updateIndex();

        amount = inPutAmount(amount, IERC20Metadata(_token).decimals());

        (uint256 userDeposit, uint256 totalDepoist) = userTotalDepoist(msg.sender);
        _deposit[msg.sender] = totalDepoist.add(amount);

        _depositIndex[msg.sender] = _depositIndexes;

        _deposits = _deposits.add(amount).add(totalDepoist.sub(userDeposit));

        amount = outPutAmount(amount, IERC20Metadata(_token).decimals());
        TransferHelper.safeTransferFrom(_token, msg.sender, address(this), amount);

        updateInterestRate();
        emit Deposit(msg.sender, _token, amount);
    }

    //Withdraw storage tokens
    function withdrawal(uint256 amount, bool all) public override {
        //Verify that the fund pool balance is sufficient, Because of loaned tokens
        require(IERC20(_token).balanceOf(address(this)) >= amount, "WSP: Insufficient fund pool balance");

        uint256 withdrawableAmount = getWithdrawableAmount(msg.sender);

        if (all) {
            amount = withdrawableAmount;
        } else {
            require(amount > 0, "WSP: amount must be > 0");
        }

        amount = inPutAmount(amount, IERC20Metadata(_token).decimals());

        require(withdrawableAmount >= amount, "WSP: Can't extract that much");

        updateIndex();

        (uint256 userDeposit, uint256 totalDepoist) = userTotalDepoist(msg.sender);
        uint256 remainingInterest = totalDepoist.sub(userDeposit);

        _deposit[msg.sender] = _deposit[msg.sender].add(remainingInterest).sub(amount);
        _deposits = _deposits.add(remainingInterest).sub(amount);

        //Then reset the index
        _depositIndex[msg.sender] = _depositIndexes;

        amount = outPutAmount(amount, IERC20Metadata(_token).decimals());
        TransferHelper.safeTransfer(_token, msg.sender, amount);

        updateInterestRate();
        emit Withdrawal(msg.sender, _token, amount);
    }

    /**
     * Lending current token
     * @param pledgeToken Token for pledge
     * @param amount Borrow amount
     */
    function borrow(address pledgeToken, uint256 amount) public virtual override {
        amount = inPutAmount(amount, IERC20Metadata(_token).decimals());

        uint256 loanableAmount = getLoanableAmount(msg.sender, pledgeToken);
        require(loanableAmount >= amount, "WSP: Can't lend that much");
        require(loanableAmount < _deposits.sub(_borrows), "WSP: Insufficient fund pool amount");

        updateIndex();

        (uint256 userBorrow, uint256 totalBorrow) = userTotalBorrow(pledgeToken, msg.sender);
        _borrow[msg.sender] = totalBorrow.add(amount);
        _borrowTokenAmount[msg.sender][pledgeToken] = totalBorrow.add(amount);
        _borrowTokenIndex[msg.sender][pledgeToken] = _borrowIndexes;
        addUserBorrowByPledge(msg.sender, pledgeToken);

        _borrows = _borrows.add(amount).add(totalBorrow.sub(userBorrow));

        IWkSwapRouter(_provider.getRouter()).addBorrowTokenPool(msg.sender, pledgeToken, address(this));

        amount = outPutAmount(amount, IERC20Metadata(_token).decimals());
        TransferHelper.safeTransfer(_token, msg.sender, amount);

        updateInterestRate();
        emit Borrow(msg.sender, pledgeToken, _token, amount);
    }

    /**
     * @dev dapp first on web check approve amount
     * @param all Whether to repay all
     * @param amount If all is true, it can be 0, otherwise it must have a value
     */
    function repay(
        address pledgeToken,
        uint256 amount,
        bool all
    ) public override {
        updateIndex();

        (uint256 userBorrow, uint256 totalBorrow) = userTotalBorrow(msg.sender, pledgeToken);
        require(totalBorrow > 0, "WSP: No need to repay");

        if (all) {
            amount = totalBorrow;
        } else {
            require(amount > 0, "WSP: amount must be > 0");
            amount = inPutAmount(amount, IERC20Metadata(_token).decimals());
        }

        ///@dev The authorized amount should be as large as possible,
        ///@dev because the number of decimal places required for calculation may be larger than that of the token
        uint256 allowanceAmount = IERC20(_token).allowance(msg.sender, address(this));
        require(allowanceAmount >= amount, "WSP: Insufficient amount of approve");

        if (all) {
            uint256 allBorrow = _borrowTokenAmount[msg.sender][pledgeToken];
            _borrowTokenAmount[msg.sender][pledgeToken] = 0;
            _borrow[msg.sender] = 0;
            _borrows = _borrows.sub(allBorrow);
            subUserBorrowByPledge(msg.sender, pledgeToken);
        } else {
            uint256 interest = totalBorrow.sub(userBorrow);

            //borrows interest add to user borrows
            _borrowTokenAmount[msg.sender][pledgeToken] = userBorrow.add(interest).sub(amount);
            _borrow[msg.sender] = _borrow[msg.sender].add(interest).sub(amount);
            _borrows = _borrows.add(interest).sub(amount);
        }

        _borrowTokenIndex[msg.sender][pledgeToken] = _borrowIndexes;

        amount = outPutAmount(amount, IERC20Metadata(_token).decimals());
        TransferHelper.safeTransferFrom(_token, msg.sender, address(this), amount);

        updateInterestRate();

        emit Repay(msg.sender, pledgeToken, _token, amount, all);
    }

    ///@return liquidationRatio liquidation Ratio
    ///@return giveToken The liquidator gets token
    ///@return getToken Token given by the liquidator
    ///@dev Tokens with 6 decimal places will also be calculated as 18
    function liquidationInfo(address user, address pledgeToken)
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
        require(_token != pledgeToken, "WSP: Cannot lend the same token");

        address pool = _getPool(pledgeToken);
        (, uint256 totalDepoist) = IWkSwapPool(pool).userTotalDepoist(user);
        (, uint256 totalBorrow) = userTotalBorrow(pledgeToken, user);

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
        giveToken = _token;
        getToken = pledgeToken;
        giveAmount = liquidationAmount.mul(95).div(100);
        liquidationFee = liquidationAmount.div(100);
        getAmount = liquidationAmount.sub(liquidationFee);
    }

    function liquidation(address user, address pledgeToken) public override {
        (
            uint256 liquidationRatio,
            address giveToken,
            ,
            uint256 giveAmount,
            uint256 getAmount,
            ,
            uint256 liquidationFee
        ) = liquidationInfo(user, pledgeToken);

        require(liquidationRatio > 0, "WSP: Unable to liquidate");

        ///@dev The number of authorizations is the same as above
        uint256 allowanceAmount = IERC20(giveToken).allowance(msg.sender, address(this));
        require(allowanceAmount >= giveAmount, "WSP: Insufficient amount of approve");

        address pool = _getPool(pledgeToken);
        (, uint256 totalDepoist) = IWkSwapPool(pool).userTotalDepoist(user);
        (, uint256 totalBorrow) = userTotalBorrow(pledgeToken, user);

        TransferHelper.safeTransfer(giveToken, _provider.getRewardPool(), liquidationFee);

        if (liquidationRatio >= 9e17) {
            _borrowTokenAmount[user][pledgeToken] = 0;
        } else {
            _borrowTokenAmount[user][pledgeToken] = _borrowTokenAmount[user][pledgeToken].sub(getAmount);
        }
        _borrow[user] = totalBorrow.sub(getAmount);

        liquidationFee = outPutAmount(liquidationFee, IERC20Metadata(_token).decimals());
        IWkSwapPool(pool).subUserDeposit(user, totalDepoist, getAmount.add(liquidationFee));

        getAmount = outPutAmount(getAmount, IERC20Metadata(_token).decimals());
        IWkSwapPool(pool).transfer(msg.sender, getAmount);
    }

    function userTotalDepoist(address user) public view override returns (uint256 userDeposit, uint256 totalDepoist) {
        userDeposit = _deposit[user];

        //Calculate the actual amount of users based on the added index
        totalDepoist = _depositIndexes.sub(_depositIndex[user]).add(BASE).mul(userDeposit).div(BASE);
    }

    function userTotalBorrow(address user, address pledgeToken)
        public
        view
        override
        returns (uint256 userBorrow, uint256 totalBorrow)
    {
        userBorrow = _borrowTokenAmount[user][pledgeToken];
        totalBorrow = _borrowIndexes.sub(_borrowTokenIndex[user][pledgeToken]).add(BASE).mul(userBorrow).div(BASE);
    }

    function getLoanableAmount(address user, address pledgeToken) public view override returns (uint256) {
        require(_token != pledgeToken, "WSP: Cannot lend the same token");

        address pool = _getPool(pledgeToken);
        (, uint256 totalDepoist) = IWkSwapPool(pool).userTotalDepoist(user);
        return
            totalDepoist.mul(_LTV).div(BASE).sub(IWkSwapRouter(_provider.getRouter()).getAllBorrow(user, pledgeToken));
    }

    function getWithdrawableAmount(address user) public view override returns (uint256) {
        uint256 totalBorrow = IWkSwapRouter(_provider.getRouter()).getAllBorrow(user, _token);

        address pool = _getPool(_token);
        (, uint256 totalDepoist) = IWkSwapPool(pool).userTotalDepoist(user);
        if (totalBorrow == 0) {
            return totalDepoist;
        } else {
            ///@notice Prevent liquidation so add 2%
            return totalDepoist.mul(_LTV.add(2e16)).div(BASE).sub(totalBorrow);
        }
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
        updateInterestRate();
    }

    function transfer(address to, uint256 amount) public override {
        require(
            _getPool(msg.sender) != address(0) && msg.sender != address(this),
            "WSP: The source of the request is not a fund pool or other fund pool"
        );
        amount = outPutAmount(amount, IERC20Metadata(_token).decimals());
        TransferHelper.safeTransfer(_token, to, amount);
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

    function getBorrowByPledge(address user) public view override returns (address[] memory) {
        uint256 count;
        for (uint256 i = 0; i < _borrowByPledge[user].length; i++) {
            if (_borrowByPledge[user][i] != address(0)) {
                count++;
            }
        }
        address[] memory a = new address[](count);
        uint256 j;
        for (uint256 i = 0; i < _borrowByPledge[user].length; i++) {
            if (_borrowByPledge[user][i] == address(0)) {
                continue;
            }
            a[j] = _borrowByPledge[user][i];
            j++;
        }
        return a;
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
        pool = _provider.getWkSwapPool(token);
        require(pool != address(0), "WSP: There is no such fund pool");
    }

    function addUserBorrowByPledge(address user, address pledgeToken) private {
        if (_borrowByPledgeIndex[user][pledgeToken] != 0) {
            return;
        }
        _borrowByPledge[user].push(pledgeToken);
        uint256 length = _borrowByPledge[user].length;
        _borrowByPledgeIndex[user][pledgeToken] = length - 1;
    }

    function subUserBorrowByPledge(address user, address pledgeToken) private {
        uint256 length = _borrowByPledgeIndex[user][pledgeToken];
        delete _borrowByPledge[user][length];
        _borrowByPledgeIndex[user][pledgeToken] = 0;
    }

    function inPutAmount(uint256 amount, uint256 decimal) private pure returns (uint256) {
        return decimal == 18 ? amount : amount.mul(1e18).div(10**decimal);
    }

    function outPutAmount(uint256 amount, uint256 decimal) private pure returns (uint256) {
        return decimal == 18 ? amount : amount.mul(10**decimal).div(1e18);
    }

    event Deposit(address user, address token, uint256 amount);

    event Withdrawal(address user, address token, uint256 amount);

    event Borrow(address user, address pledgeToken, address borrowToken, uint256 amount);

    event Repay(address user, address pledgeToken, address borrowToken, uint256 amount, bool all);

    event UpdateIndex(uint256 depositIndexes, uint256 borrowIndexes);

    event UpdateInterestRate(uint256 depositAnnualInterestRate, uint256 borrowAnnualInterestRate);
}
