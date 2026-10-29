
const s1plusVault = {
  "portfolio1": "0x40209e58D76492387eab68607F3731F4c4faB24c",
  "portfolio2": "0xeEA32E607235Ca6A18e2FC30Bb22421d9E2A7564",
  "portfolio3": "0x96c1FA3793804e140E5c4a6A91966485d677c6aD",
}

const bnbplusVault = {
  "portfolio1": "",
}

export const BSC_TEST_CONTRACTS = {

  "s1plusVault": s1plusVault,
  "bnbplusVault": bnbplusVault,

  // backend signer for EIP712
  "signer": "0x5bf5B2646720eC08d70A00715dA3FE767ac3D8A1",

   // test tokens
  "BBTC" : "0x4636E9e38121d3bB7773Ff63a85d1bF97c17d00f",
  "USD1" : "0xB9951cd2921f72AE7f2d7C9ec2036bAD80076085",
  "USDT" : "0x85ADed50BB0896AbC44CD0D8FC3818C227473121",
  "USDC" : "0x2E3A8b87B447440921fd877459880C963971f7e0",

  // implementation of vaults
  "BBTCVaultImpl": "",
  // "USD1VaultImpl": "0xd868e13b8e7c480c08e9Db8fBC8eF7c28a7B8Ba7",
  "USD1VaultImpl": "0x400B6A4336d79F1bffD14e35888bc9Bcb458298E",    // 9.1 升级
  "USD1PlusVaultImpl": "0x2B87A5CF4a5d8181C040576D91000A4F83F0E4a7",

  // manager
  "CeDeFiManager": "0x06DD4dC8d58F50a5FE1d4C1766D0a24828C52A03",

  // vaults
  // "USD1Vault": "0x9f906df9C3fDc5CbFd4BAc484EAB0e71Dd797969",  // 单一underlying
  "sUSD1PlusVault": "0xdBb238620B96e3F5B2Fe9E1620040Ac2A9CEa1C0",  // 多underlying
  "USD1PlusVault": "0x3FAf36d4d3Bdc5678D2B928Ba9B125733a5513AD",

  "BNBPlusVault": "0x22465782Fd1738c5a42b68e3ff8210415e9C4B34" // BNB+ vault
}

