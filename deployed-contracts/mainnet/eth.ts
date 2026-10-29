export const ETH_Contracts = {
  // admin
  "adminRole": "0x60707DFd714C3Ac2f086D284145cD8Cc6915262f",

  // portfolios
  "portfolio1": "0xa20f09184d7d6f4a6e803666c0d6d927cbb876d5",  // cobo mpc

  // backend signer for EIP712
  "signer": "0x63221caddd5641c81a7365fe3a0dfab4ff6ae2fd",

  // mainnet tokens
  "USD1": "0x8d0D000Ee44948FC98c9B98A4FA4921476f08B0d",
  "USDT": "0xdAC17F958D2ee523a2206206994597C13D831ec7",
  "USDC": "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",

  // deployed contracts
  "CeDeFiManager": "0xc8c80c14b8e57080a801951a436ddf456e477f75",
  "sUSD1PlusVault": "0x8f18f2c97d2f5ec0e1d5b91c1d2ce245a9151972",

  // Implementations of Proxy Contracts, used for verifying source code
  "CeDeFiManagerImpl": "0xa4b0aadcca2fa9278d89bd48579acdd4dc3658ad",
  // 使用确定性部署的初始版本
  // "sUSD1PlusVaultImpl": "0x30152540233a05e40b9431572b0ff5525a3d231e",

  // 8.19 版本, 解决获取unit nav 数据错误的问题
  // "sUSD1PlusVaultImpl": "0x4808601862B019b25697794cC51f33bEB5757ad5",

  // 9.10 版本, 支持ccip. commit id: 5aa44e59ff134946273959eacfdbb960479aabd1
  // "sUSD1PlusVaultImpl": "0x6E0F4dC0D748e4917b418357d989B2023b8B7a20",

  // 20260818 支持ceffu入金账号需要白名单需求. commit id: ae53006bbb0d64fb89b21780c44403b8b3c65200
  "sUSD1PlusVaultImpl": "0xa8e3A7B2FE9CA11A6E99C9057E0Ca62774Db792B",
}