import { ethers } from "hardhat";

async function main() {
  // Deploy REX Protocol Token
  const REX = await ethers.getContractFactory("REXProtocolToken");
  const rex = await REX.deploy();
  console.log("REX Protocol Token deployed to:", rex.address);

}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
