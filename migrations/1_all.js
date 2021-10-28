const WkSwapProvider = artifacts.require("WkSwapProvider");
const RewardPool = artifacts.require("RewardPool");
const WkSwapRouter = artifacts.require("WkSwapRouter");

const WDai = artifacts.require("WDai");
const WUsdc = artifacts.require("WUsdc");
const WUsdt = artifacts.require("WUsdt");

module.exports = async (deployer, network) => {
    await deployer.deploy(WkSwapProvider);
    const provider = await WkSwapProvider.deployed();

    await deployer.deploy(RewardPool);
    const rewardPool = await RewardPool.deployed();

    await deployer.deploy(WkSwapRouter, provider.address);
    const router = await WkSwapRouter.deployed();

    await provider.setRewardPool(rewardPool.address);
    await provider.setRouter(router.address);

    if (network === 'development') {
        await deployer.deploy(WUsdt);
        await deployer.deploy(WDai);
        await deployer.deploy(WUsdc);
    }
};
