const {ethers, upgrades} = require("hardhat");

async function main() {
  const vaultAddress = "0x7c09733834873b1FDB8A70c19eE1A514023f74f9"; // Ethos Reserve WETH Vault 2.1

  const Strategy = await ethers.getContractFactory("ReaperStrategyYearnFarmer");

  const strategists = [
    "0x1E71AEE6081f62053123140aacC7a06021D77348", // bongo
    "0x81876677843D00a7D792E1617459aC2E93202576", // degenicus
    "0xC91184A87335AbAf0Fb75356a94eFA57E5852c81", // Yuvi
    "0x4C3490dF15edFa178333445ce568EC6D99b5d71c", // eidolon
    "0xb26cd6633db6b0c9ae919049c1437271ae496d15", // zokunei
    "0x60BC5E0440C867eEb4CbcE84bB1123fad2b262B1", // goober
  ];
  const multisigRoles = [
    "0x9BC776dBb134Ef9D7014dB1823Cd755Ac5015203", // super admin
    "0xeb9C9b785aA7818B2EBC8f9842926c4B9f707e4B", // admin
    "0xb0C9D5851deF8A2Aac4A23031CA2610f8C3483F9", // guardian
  ];
  const keepers = [
    "0x33D6cB7E91C62Dd6980F16D61e0cfae082CaBFCA",
    "0x34Df14D42988e4Dc622e37dc318e70429336B6c5",
    "0x36a63324edFc157bE22CF63A6Bf1C3B49a0E72C0",
    "0x51263D56ec81B5e823e34d7665A1F505C327b014",
    "0x5241F63D0C1f2970c45234a0F5b345036117E3C2",
    "0x5318250BD0b44D1740f47a5b6BE4F7fD5042682D",
    "0x55a078AFC2e20C8c20d1aa4420710d827Ee494d4",
    "0x73C882796Ea481fe0A2B8DE499d95e60ff971663",
    "0x7B540a4D24C906E5fB3d3EcD0Bb7B1aEd3823897",
    "0x8456a746e09A18F9187E5babEe6C60211CA728D1",
    "0x87A5AfC8cdDa71B5054C698366E97DB2F3C2BC2f",
    "0x9a2AdcbFb972e0EC2946A342f46895702930064F",
    "0xd21e0fe4ba0379ec8df6263795c8120414acd0a3",
    "0xe0268Aa6d55FfE1AA7A77587e56784e5b29004A2",
    "0xf58d534290Ce9fc4Ea639B8b9eE238Fe83d2efA6",
    "0xCcb4f4B05739b6C62D9663a5fA7f1E2693048019",
  ];

  const swapper = "0x1FFa0AF1Fa5bdfca491a21BD4Eab55304c623ab8";
  const yearnVault = "0x5B977577Eb8a480f63e11FC615D6753adB8652Ae";
  const stakingRewards = "0xE35Fec3895Dcecc7d2a91e8ae4fF3c0d43ebfFE0";
  const shouldStake = true;
  
  const strategy = await upgrades.deployProxy(
    Strategy,
    [
      vaultAddress,
      swapper,
      strategists,
      multisigRoles,
      keepers,
      yearnVault,
      stakingRewards,
      shouldStake,
    ],
    {kind: "uups", timeout: 0},
  );

  await strategy.deployed();
  console.log("Strategy deployed to:", strategy.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
