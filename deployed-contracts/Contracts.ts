import { MainnetContracts } from "./mainnet";
import { TestnetContracts } from "./testnet";

export const Contracts = {
  mainnet: MainnetContracts,
  testnet: TestnetContracts,
};

// 主网
export const TargetChain = Contracts.mainnet;
// 测试网
export const DebugContracts = Contracts.testnet;