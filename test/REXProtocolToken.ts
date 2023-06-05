import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";

// Tests against a fork of Polygon network
const ricHolderAddress = "0x3226c9eac0379f04ba2b1e1e1fcd52ac26309aea";
const ricTokenAddress = "0x263026E7e53DBFDce5ae55Ade22493f828922965";

describe("RicochetLiquidityNetwork", function () {
  let rexToken, ricToken, ricHolder;

  async function impersonateAccount(account: string) {
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [account],
    });

    // Set a balance for the account
    await hre.network.provider.send("hardhat_setBalance", [
      account,
      "0x100000000000000000000"
    ]);

    return ethers.provider.getSigner(account);
  }

  // Deploy the contracts using the fixture
  async function deployRicochetLiquidityNetwork() {
    
    // Deploy REXProtocolToken
    const REXProtocolToken = await ethers.getContractFactory("REXProtocolToken");
    rexToken = await REXProtocolToken.deploy();

    // Impersonate ricHolder
    ricHolder = await impersonateAccount(ricHolderAddress);

    // Get the RIC token instance
    ricToken = await ethers.getContractAt("ERC20", ricTokenAddress);
    
    return { rexToken, ricToken, ricHolder };
  }

  it("Should burn RIC and mint REX", async function () {
    // Deploy the contracts
    const { rexToken, ricToken, ricHolder } = await loadFixture(deployRicochetLiquidityNetwork);

    // Get the initial RIC balance of the ricHolder
    const ricBalance = await ricToken.balanceOf(ricHolderAddress);

    // Get the initial total supply of RIC
    const ricTotalSupply = await ricToken.totalSupply();

    // Burn RIC and mint REX
    await ricToken.connect(ricHolder).approve(rexToken.address, ricBalance);
    await rexToken.connect(ricHolder).supportREX(ricBalance);

    // Check the REX balance of the ricHolder
    const rexBalance = await rexToken.balanceOf(ricHolderAddress);
    expect(rexBalance).to.equal(ricBalance);

    // Check the RIC balance of the ricHolder
    const ricBalanceAfter = await ricToken.balanceOf(ricHolderAddress);
    expect(ricBalanceAfter).to.equal(0);

    // Check the total supply of REX
    const totalSupply = await rexToken.totalSupply();
    expect(totalSupply).to.equal(ricBalance);

  });

    
});
