import { ethers } from "hardhat";
import path from "path";
import { TypedDataDomain } from "ethers";

export async function preDeploy() {
  const [boss, admin, operator, player1, player2, player3, signer1, portfolio1, portfolio2, portfolio3] = await ethers.getSigners();

  const BBTC = await ethers.deployContract("TestToken", ["Test BBTC", "BBTC"]);
  await BBTC.waitForDeployment();

  const USD1 = await ethers.deployContract("TestToken", ["Test USD1", "USD1"]);
  await USD1.waitForDeployment();

  const USDT = await ethers.deployContract("TestToken", ["Test USDT", "USDT"]);
  await USDT.waitForDeployment();

  const USDC = await ethers.deployContract("TestToken", ["Test USDC", "USDC"]);
  await USDC.waitForDeployment();

  const ManagerImpl = await ethers.deployContract("CeDeFiManager");
  await ManagerImpl.waitForDeployment();

  const initdata = ManagerImpl.interface.encodeFunctionData(
    'initialize',
    [
      boss.address,
      admin.address
    ]
  );
  const ManagerProxy = await ethers.deployContract("ERC1967Proxy", [ManagerImpl.target, initdata]);
  await ManagerProxy.waitForDeployment();

  const CeDeFiManager = await ethers.getContractAt('CeDeFiManager', ManagerProxy.target);
  // add support functions
  const Vault =  new ethers.Interface(require(path.join(__dirname, '..', 'artifacts/contracts/vaults/USD1/sUSD1PlusVault.sol/sUSD1PlusVault.json')).abi);
  await CeDeFiManager.connect(admin).setInvokableVaultsFuncs([
    Vault.getFunction('updatePortfolios')!.selector,
    Vault.getFunction('setMinDepositAmount')!.selector,
    Vault.getFunction('setMinWithdrawAmount')!.selector,
    Vault.getFunction('setUnitNav')!.selector,
    Vault.getFunction('addBlacklist')!.selector,
    Vault.getFunction('removeBlacklist')!.selector,
    Vault.getFunction('freezeShares')!.selector,
    Vault.getFunction('unfreezeShares')!.selector,
    Vault.getFunction('setTransferable')!.selector,
    Vault.getFunction('pause')!.selector,
    Vault.getFunction('unpause')!.selector,
    Vault.getFunction('setSigner')!.selector,
    Vault.getFunction('setAcceptUnderlying')!.selector,
    Vault.getFunction('setRole')!.selector,
  ], [ true, true, true, true, true, true, true, true, true, true, true, true, true, true]);


  const MultiSendImpl = await ethers.deployContract("MultiSend");
  await MultiSendImpl.waitForDeployment();

  const msInitdata = MultiSendImpl.interface.encodeFunctionData(
    'initialize',
    [admin.address]
  );
  const MultiSendProxy = await ethers.deployContract("ERC1967Proxy", [MultiSendImpl.target, msInitdata]);
  await MultiSendProxy.waitForDeployment();

  const MultiSend = await ethers.getContractAt("MultiSend", MultiSendProxy.target);

  return {boss, admin, operator, player1, player2, player3, signer1, CeDeFiManager, BBTC, USD1, USDT, USDC, portfolio1, portfolio2, portfolio3, MultiSend};
}


export async function getClaimSinature(
  operator: any,
  name: string,
  version: string,
  contract: string,
  period: bigint,
  user: string,
  sharesAmount: bigint,
  txHash: string
) {
  const domain: TypedDataDomain = {
    name,
    version,
    verifyingContract:contract,
    chainId: (await ethers.provider.getNetwork()).chainId
  };
// uint128 period,address user,uint256 sharesAmount
  const types = {
    "ConfirmShare":[
      {name: "period", type: "uint128"},
      {name: "txHash", type: "bytes32"},
      {name: "user", type: "address"},
      {name: "sharesAmount", type: "uint256"},
    ]
  };

  const values = {
    period,
    txHash,
    user,
    sharesAmount,
  };

  const signature = await operator.signTypedData(domain, types, values);
  return signature;
}