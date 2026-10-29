import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import * as dotenv from "dotenv";
dotenv.config();

const accounts =
  process.env.PK !== undefined ? [process.env.PK] :
    (process.env.DEFAULT_PKS ?? "").split(",").filter(Boolean);

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
      bsc: process.env.BSCSCAN_API_KEY ?? "",
      bscTestnet: process.env.BSCSCAN_API_KEY ?? "",
      mainnet: process.env.ETHERSCAN_MAINNET_API_KEY ?? ""
    }
  },
  networks: {
    hardhat: {
      chainId: 1337,
      allowUnlimitedContractSize: true
    },
    eth: {
      url: process.env.ETH_INFURA_URL ?? "",
      accounts: [process.env.ETH_MAINNET_KEY!],
    },
    node: {
      url: "http://13.208.44.230:8545",
      accounts,
    },
    sepolia: {
      url: "https://eth-sepolia.public.blastapi.io",
      accounts: [process.env.ETH_SEPOLIA_KEY!],
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
      accounts: [process.env.BSC_MAINNET_KEY!]
    },
    base: {
      // url: "https://mainnet.base.org",
      url: process.env.BASE_MAINNET_URL ?? "",
      accounts
    },
    basetest: {
      url: "https://sepolia.base.org",
      // url: "https://base-sepolia.blockpi.network/v1/rpc/public",
      // url: "https://base-sepolia-rpc.publicnode.com",
      accounts: [process.env.BASE_TESTNET_KEY!]
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
