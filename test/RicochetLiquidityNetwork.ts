import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers } from "hardhat";

// Tests against a fork of Polygon network
const selfCompounderAddress = "0xad58D1DF63AFcf090Cc930475db3dD3cD8f739eA";
const compounderAddress = "0x5411894842e610C4D0F6Ed4C232DA689400f94A1";
const gelatoAutomateAddress = "0x527a819db1eb0e34426297b03bae11F2f8B3A19E";
const nonfungiblePositionManagerAddress = "0xC36442b4a4522E871399CD717aBDD847Ab11FE88";
const uniswapRouterAddress = "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45";
const gelatoNetworkAddress = "0x7598e84B2E114AB62CAB288CE5f7d5f6bad35BbA";

// RIC-USDC (0.05%) LP
const ricUsdcLPOwnerAddress = "0xd978f6AE3377C1A2Bd74741adA0398B7FE16BA01";
const ricUsdcLPId = "808249"; // This one has some fees to collect as of block 43489992

// RIC-WMATIC (0.05%) LP
const ricWmaticLPOwnerAddress = "0x14aD7D958ab2930863B68E7D98a7FDE6Ae4Cd12f";
const ricWmaticLPId = "904234";

describe("RicochetLiquidityNetwork", function () {
  let rexNet, nonfungiblePositionManager, ricUsdcLp, ricWmaticLp, gelatoNetwork, ops;

  async function impersonateAccount(account) {
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
    const RicochetLiquidityNetwork = await ethers.getContractFactory("RicochetLiquidityNetwork");
    rexNet = await RicochetLiquidityNetwork.deploy(
      selfCompounderAddress,
      gelatoAutomateAddress,
      nonfungiblePositionManagerAddress,
      uniswapRouterAddress
    );

    // Get the contract instances for dependencies
    nonfungiblePositionManager = await ethers.getContractAt("INonfungiblePositionManager", nonfungiblePositionManagerAddress);
    ops = await ethers.getContractAt('Ops', gelatoAutomateAddress)

    // Impersonate the LP owners and Gelato Network
    ricUsdcLp = await impersonateAccount(ricUsdcLPOwnerAddress);
    ricWmaticLp = await impersonateAccount(ricWmaticLPOwnerAddress);
    gelatoNetwork = await impersonateAccount(gelatoNetworkAddress);

    // Withdraw the RIC-USDC LP NFT from the compounder contract:
    // Check the initial state of the LP position
    let compounder = await ethers.getContractAt("ICompoundor", compounderAddress);
    await compounder.connect(ricUsdcLp).withdrawToken(ricUsdcLPId, ricUsdcLPOwnerAddress, false, '0x');
    
    return { rexNet, nonfungiblePositionManager, ricUsdcLp, gelatoNetwork, ops };
  }

  it("Should automatically compound fees", async function () {
    const { rexNet, nonfungiblePositionManager, ricUsdcLp, gelatoNetwork, ops } = await loadFixture(deployRicochetLiquidityNetwork);

    // Execute a small collect on the position to get the value for tokensOwed0 and tokensOwed1
    await nonfungiblePositionManager.connect(ricUsdcLp).collect({
      tokenId: ricUsdcLPId,
      recipient: ricUsdcLPOwnerAddress,
      amount0Max: 1,
      amount1Max: 1
    });
    let initPosition = await nonfungiblePositionManager.positions(ricUsdcLPId);

    // Transfer the RIC-USDC LP NFT, expect the NFTDeposited event to be emitted on transfer
    await expect(nonfungiblePositionManager.connect(ricUsdcLp).safeTransferFrom(ricUsdcLPOwnerAddress, rexNet.address, ricUsdcLPId))
      .to.emit(rexNet, "NFTDeposited");
    
    // Check that the Uniswap V3 LP NFT is now owned by rexNet
    expect(await nonfungiblePositionManager.ownerOf(ricUsdcLPId)).to.equal(rexNet.address);
    expect(await rexNet.uniswapNFTs(0)).to.equal(ricUsdcLPId);

    // Get the block number for encoding args for the gelato executor
    let gelatoBlock = await ethers.provider.getBlock('latest')

    // Setup gelato executor exec and module data
    let encodedArgs = ethers.utils.defaultAbiCoder.encode(['uint128', 'uint128'], [gelatoBlock.timestamp, 60])
    let execData = rexNet.interface.encodeFunctionData('compound', [ricUsdcLPId])
    let moduleData = {
      modules: [1],
      args: [encodedArgs],
    }

    // Submit task to gelato
    await ops.connect(gelatoNetwork).exec(
      rexNet.address,
      rexNet.address,
      execData,
      moduleData,
      '1', // 1 gas units for the `compound` txn
      '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE',
      false,
      true
    );

    // Check the state of the LP position after compounding
    let finalPosition = await nonfungiblePositionManager.positions(ricUsdcLPId);
    expect(finalPosition.tokensOwed0).to.be.below(initPosition.tokensOwed0);
    expect(finalPosition.tokensOwed1).to.be.below(initPosition.tokensOwed1);

    // Confirm the NFT has made it back to REX Network
    expect(await nonfungiblePositionManager.ownerOf(ricUsdcLPId)).to.equal(rexNet.address);

  });

    
});
