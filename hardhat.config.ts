import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import * as dotenv from "dotenv";
dotenv.config();

const accounts =
  process.env.PK !== undefined ? [process.env.PK] :
    [
      // all belowing private keys are build in accounts in hardhat,
      "***REMOVED***", // 0x11e07aed82f1210ddab32fcd9419f56162b2794f
      "***REMOVED***", // 0xe87bde923b1b0b48c2f9f946c386f30d1184458e
      "***REMOVED***", // 0x761eb5fc4fed1a96a2a2ab6f5be8516c50e3007b
      "***REMOVED***", // 0xa994a8c305cba5932ec30f1331155035b09bf391
      "***REMOVED***"  // 0xa3f45b3ab5ff54d24d61c4ea3f39cc98ebcb3c7e
    ];

const config: HardhatUserConfig = {
  solidity: {
    version:"0.8.28",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  etherscan: {
    apiKey: {
      bsc: '***REMOVED***',
      bscTestnet: '***REMOVED***',
    }
  },
  networks: {
    hardhat: {
      chainId: 1337,
      allowUnlimitedContractSize: true
    },
    amoy: {
      url: "https://rpc-amoy.polygon.technology",
      accounts,
    },
    node: {
      url: "http://13.208.44.230:8545",
      accounts,
    },
    sepolia: {
      url: "https://eth-sepolia.public.blastapi.io",
      accounts,
    },
    polygon: {
      url: "https://polygon.llamarpc.com",
      accounts,
    },
    bitlayer_test: {
      url: "https://testnet-rpc.bitlayer.org",
      gasPrice: 1000000000,
      chainId: 200810,
      accounts
    },
    bitlayer: {
      url: "https://mainnet-rpc.bitlayer.org",
      accounts,
      chainId: 200901,
      gasPrice: 1000000000,
    },
    hecotest: {
      // url: "http://47.118.37.70:8545",
      url: "https://http-testnet.hecochain.com",
      gas: 6000000,
      accounts
    },
    mainnet: {
      url: "https://http-mainnet.hecochain.com",
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
    bsctest: {
      url: 'https://bsc-testnet.public.blastapi.io',
      accounts: [process.env.BSC_TESTNET_KEY!]
    },
    bsc: {
      url: "https://bsc-rpc.publicnode.com",
      accounts
    },
    base: {
      // url: "https://mainnet.base.org",
      url: "https://twilight-thrumming-diamond.base-mainnet.quiknode.pro/***REMOVED***",
      accounts
    },
    basetest: {
      url: "https://sepolia.base.org",
      // url: "https://base-sepolia.blockpi.network/v1/rpc/public",
      // url: "https://base-sepolia-rpc.publicnode.com",
      accounts
    },
    auroratest: {
      url: "https://testnet.aurora.dev/",
      gas: 6000000,
      chainId: 1313161555,
      accounts
    },
  },
  // gasReporter: {
  //   enabled: true,
  //   currency: "USD",
  // },
  // etherscan: {
  //   apiKey: process.env.ETHERSCAN_API_KEY,
  // },
};

export default config;
