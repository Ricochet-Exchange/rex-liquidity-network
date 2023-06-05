import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-gas-reporter";
import * as tdly from "@tenderly/hardhat-tenderly";

tdly.setup();

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.18",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      viaIR: true,
    },
  },
  networks: {
    hardhat: {
      forking: {
        url: process.env.POLYGON_NODE_URL || "",
        accounts: [],
        enabled: true, 
        chainId: 137,
      },
    },
    tenderly: {
      chainId: Number(process.env.TENDERLY_NETWORK_ID),
      accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
      url: process.env.TENDERLY_NODE_URL,
    },
  },
  tenderly: {
    username: String(process.env.TENDERLY_USERNAME), 
    project: "rex-protocol",
    forkNetwork: process.env.TENDERLY_NETWORK_ID, 
    privateVerification: false,
  },
  gasReporter: {
    enabled: true
  },
};

export default config;
