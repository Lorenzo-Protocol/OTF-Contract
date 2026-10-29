export const BSC_Contracts = {
  // admin
  "adminRole": "0x60707DFd714C3Ac2f086D284145cD8Cc6915262f",
  // susd1+ portfolios
  "portfolio1": "0x424cbf009a6f90f53c4a3e938b94044df199e54e",  // cobo mpc

  // bnb+ portfolios
  // "portfolioBnb": "0x2BF26B9B65e46a743902562983E81296Bd343819",  // hg bnb wallet for BNB+
  "portfolioBnb": "0xcd80a6ee5e523acd30c34b1d9c6569a6f77efa06",  // hg bnb wallet for BNB+

  // backend signer for EIP712
  "signer": "0x63221caddd5641c81a7365fe3a0dfab4ff6ae2fd",

  // mainnet tokens
  "USD1": "0x8d0d000ee44948fc98c9b98a4fa4921476f08b0d",
  "USDT": "0x55d398326f99059ff775485246999027b3197955",
  "USDC": "0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d",

  // deployed contracts
  "CeDeFiManager": "0x507ec48EF26919a205a9f3b8AaF69532e20c0987",
  "sUSD1PlusVault": "0x4F2760B32720F013E900DC92F65480137391199b",
  "USD1PlusVault": "0xAeFc9CEce593B28FAead5c096856d68082254867",
  "BNBPlusVault": "0x5D5721Bf35BDfFBa64E7b8fCeeb4712904a0DD11",


  // Implementations of Proxy Contracts, used for verifying source code
  // "CeDeFiManagerImpl": "0x91e93870d5975C58f2D9D90858EAd90D059cf199", // 7.12日版本
  "CeDeFiManagerImpl": "0x6E0F4dC0D748e4917b418357d989B2023b8B7a20",  // 10.17日版本
  // "sUSD1PlusVaultImpl": "0xCc88F9E7c448ce5b0730F65Fa7a9aAb2738e773D",
  // "sUSD1PlusVaultImpl": "0xF634a63697FEEEB4a88eAab57A0A0F31F1D31DeE", // 8.6 增加view方法getCurrentUnitNav
  // "sUSD1PlusVaultImpl": "0x3a9909B87fF6a3FD23F2711b96866Ac353C1B3Ee", // 8.19 解决获取unit nav 数据错误的问题
  // "sUSD1PlusVaultImpl": "0x103E63266f9A7B05b833F4964880A7EcE5407968", // 9.10 版本, 支持ccip. commit id: 5aa44e59ff134946273959eacfdbb960479aabd1

  // 20260818 支持ceffu入金账号需要白名单需求. commit id: 578a48cbf7897b94067fadd688269b923e50bed8
  "sUSD1PlusVaultImpl": "0x972c27ee69b19d7648cef365700c22713a9a31fd",


  "USD1PlusVaultImpl": "0xc536323E3a4D543ceCEcE0aedD973E0e0ea25C47",
}