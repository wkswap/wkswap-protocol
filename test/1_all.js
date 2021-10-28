'use strict'

const { assert } = require('chai')
const BN = require('bn.js')
const DECIMAL18 = new BN('1000000000000000000')
const DECIMAL6 = new BN('1000000')

//8e17
const LTV = new BN('800000000000000000');

const WkSwapProvider = artifacts.require('WkSwapProvider')
const WkSwapPool = artifacts.require('WkSwapPool')
const WkSwapRouter = artifacts.require('WkSwapRouter')

const WDai = artifacts.require("WDai");
const WUsdc = artifacts.require("WUsdc");
const WUsdt = artifacts.require("WUsdt");

let daiPoolAddress;
let usdtPoolAddress;
let usdcPoolAddress;

contract("WkSwap", async (accounts) => {

    before(async () => {
        const wDai = await WDai.deployed();
        const wUsdc = await WUsdc.deployed();
        await wDai.mint({ from: accounts[0] });
        await wUsdc.mint({ from: accounts[1] });
    });

    it("Create pools", async () => {
        const wDai = await WDai.deployed();
        const wUsdc = await WUsdc.deployed();
        const wUsdt = await WUsdt.deployed();

        const provider = await WkSwapProvider.deployed();

        let data = await provider.createPool(wDai.address, LTV);
        daiPoolAddress = data.logs[0].args._pool;
        assert.exists(daiPoolAddress);

        data = await provider.createPool(wUsdc.address, LTV);
        usdcPoolAddress = data.logs[0].args._pool;
        assert.exists(usdcPoolAddress);

        data = await provider.createPool(wUsdt.address, LTV);
        usdtPoolAddress = data.logs[0].args._pool;
        assert.exists(usdtPoolAddress);
    });

    it("Deposit", async () => {
        const wkSwapPool = await WkSwapPool.at(daiPoolAddress);

        const wDai = await WDai.deployed();
        try {
            await wkSwapPool.deposit(DECIMAL18);
        } catch (error) {
            assert.equal(error.reason, "WSP: Insufficient allowance amount");
        }

        await wDai.approve(wkSwapPool.address, DECIMAL18.mul(new BN(100)));
        await wkSwapPool.deposit(DECIMAL18.mul(new BN(2)));

        const deposit = await wkSwapPool.getDeposit.call(accounts[0]);
        assert.equal(deposit.toString(), DECIMAL18.mul(new BN(2)).toString());
    });

    it("Withdrawal", async () => {
        const wkSwapPool = await WkSwapPool.at(daiPoolAddress);

        await wkSwapPool.withdrawal(DECIMAL18, false);

        const deposit = await wkSwapPool.getDeposit.call(accounts[0]);
        assert.equal(deposit.toString(), DECIMAL18.toString());
    });

    it("Withdrawal all", async () => {
        const wkSwapPool = await WkSwapPool.at(daiPoolAddress);

        await wkSwapPool.withdrawal(0, true);

        const deposit = await wkSwapPool.getDeposit.call(accounts[0]);
        assert.equal(deposit.toString(), 0);
    });

    it("borrow", async () => {
        const daiPool = await WkSwapPool.at(daiPoolAddress);
        const usdcPool = await WkSwapPool.at(usdcPoolAddress);

        const wDai = await WDai.deployed();
        await wDai.approve(daiPool.address, DECIMAL18.mul(new BN(100)), { from: accounts[0] });

        const wUsdc = await WUsdc.deployed();
        await wUsdc.approve(usdcPool.address, DECIMAL6.mul(new BN(100)), { from: accounts[1] });

        await daiPool.deposit(DECIMAL18.mul(new BN(2)), { from: accounts[0] });
        await usdcPool.deposit(DECIMAL6.mul(new BN(2)), { from: accounts[1] });

        const deposit0 = await daiPool.getDeposit.call(accounts[0]);
        assert.equal(deposit0.toString(), DECIMAL18.mul(new BN(2)));

        const deposit1 = await usdcPool.getDeposit.call(accounts[1]);
        assert.equal(deposit1.toString(), DECIMAL18.mul(new BN(2)));

        try {
            await daiPool.borrow(wUsdc.address, DECIMAL18.mul(new BN(2)), { from: accounts[1] });
        } catch (error) {
            assert.equal(error.reason, "WSP: Can't lend that much");
        }

        await daiPool.borrow(wUsdc.address, DECIMAL18, { from: accounts[1] });

        const daiBalance = await wDai.balanceOf.call(accounts[1]);
        assert.equal(daiBalance.toString(), DECIMAL18.toString());

        const pledges = await daiPool.getBorrowByPledge.call(accounts[1]);
        assert.equal(wUsdc.address, pledges[0]);

        const totalBorrow = await daiPool.userTotalBorrow(accounts[1], wUsdc.address);
        assert.equal(totalBorrow.userBorrow.toString(), totalBorrow.totalBorrow.toString(), DECIMAL18.toString());

        try {
            await usdcPool.borrow(wDai.address, DECIMAL18, { from: accounts[0] });
        } catch (error) {
            assert.equal(error.reason, "WSP: Can't lend that much");
        }

        await usdcPool.borrow(wDai.address, DECIMAL6, { from: accounts[0] });

        const usdcBalance = await wUsdc.balanceOf.call(accounts[0]);
        assert.equal(usdcBalance.toString(), DECIMAL6.toString());

    });

});
