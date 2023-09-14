import * as dotenvenc from "@chainlink/env-enc";
dotenvenc.config();

import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "./tasks";

const PRIVATE_KEY = process.env.PRIVATE_KEY;
const ETHEREUM_SEPOLIA_RPC_URL = process.env.ETHEREUM_SEPOLIA_RPC_URL;
const ETHEREUM_GOERLI_RPC_URL = process.env.ETHEREUM_GOERLI_RPC_URL;
const AVALANCHE_FUJI_RPC_URL = process.env.AVALANCHE_FUJI_RPC_URL;

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      { version: "0.8.19" },
      { version: "0.7.6" },
      // { version: "0.4.19" },
      // { version: "0.6.12" },
    ],
  },
  networks: {
    hardhat: {
      chainId: 31337,
    },
    ethereumSepolia: {
      url:
        ETHEREUM_SEPOLIA_RPC_URL !== undefined ? ETHEREUM_SEPOLIA_RPC_URL : "",
      accounts: PRIVATE_KEY !== undefined ? [PRIVATE_KEY] : [],
      chainId: 11155111,
    },
    avalancheFuji: {
      url: AVALANCHE_FUJI_RPC_URL !== undefined ? AVALANCHE_FUJI_RPC_URL : "",
      accounts: PRIVATE_KEY !== undefined ? [PRIVATE_KEY] : [],
      chainId: 43113,
    },
    ethereumGoerli: {
      url: ETHEREUM_GOERLI_RPC_URL !== undefined ? ETHEREUM_GOERLI_RPC_URL : "",
      accounts: PRIVATE_KEY !== undefined ? [PRIVATE_KEY] : [],
      chainId: 5,
    },
  },
  typechain: {
    externalArtifacts: ["./abi/*.json"],
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
};

export default config;
