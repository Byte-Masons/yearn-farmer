const {ethers} = require("hardhat");

async function main() {
  const Strategy = await ethers.getContractFactory("ReaperStrategyYearnFarmer");

  const strategyAddress = "0x1Df9F3A494Cd8A9743D85f003952d3e923913D6B";
  const strategy = Strategy.attach(strategyAddress);

  const wethAddress = "0x4200000000000000000000000000000000000006";
  const opAddress = "0x4200000000000000000000000000000000000042";

  const univ3 = "0xE592427A0AEce92De3Edee1F18E0157C05861564";

  const UNIV3 = 3n;

  
  const step0 = {
    exType: UNIV3,
    start: opAddress,
    end: wethAddress,
    minAmountOutData: {
      kind: 1n,
      absoluteOrBPSValue: 9900n,
    },
    exchangeAddress: univ3,
  };

  const steps = [step0];
  await strategy.setHarvestSwapSteps(steps);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
