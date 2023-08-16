const {ethers, upgrades} = require("hardhat");

async function main() {
  const Swapper = await ethers.getContractFactory("ReaperSwapper");

  const strategists = [
    "0x1E71AEE6081f62053123140aacC7a06021D77348", // bongo
    "0x81876677843D00a7D792E1617459aC2E93202576", // degenicus
    "0x1A20D7A31e5B3Bc5f02c8A146EF6f394502a10c4", // tess
    "0x4C3490dF15edFa178333445ce568EC6D99b5d71c", // eidolon
    "0xb26cd6633db6b0c9ae919049c1437271ae496d15", // zokunei
    "0x60BC5E0440C867eEb4CbcE84bB1123fad2b262B1", // goober
  ];
  const guardian = "0xb0C9D5851deF8A2Aac4A23031CA2610f8C3483F9";
  const superAdmin = "0x9BC776dBb134Ef9D7014dB1823Cd755Ac5015203";

  const swapper = await upgrades.deployProxy(
    Swapper,
    [
      strategists,
      guardian,
      superAdmin,
    ],
    {kind: "uups", timeout: 0},
  );
  console.log("Swapper deployed to:", swapper.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
