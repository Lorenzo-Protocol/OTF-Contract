import { ethers } from "hardhat";
import path from "path";

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
  const Vault =  new ethers.Interface(require(path.join(__dirname, '..', 'artifacts', 'contracts', 'vaults', 'Vault.sol', 'Vault.json')).abi);
  await CeDeFiManager.connect(admin).addAllowedVaultsFuncs([
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
  ], [true, true, true, true, true, true, true, true, true, true, true]);

  return {boss, admin, operator, player1, player2, player3, signer1, CeDeFiManager, BBTC, USD1, USDT, USDC, portfolio1, portfolio2, portfolio3};
}