import { ethers } from "hardhat";

export async function preDeploy() {
  const [boss, admin, operator, player1, player2, player3, portfolio1, portfolio2, portfolio3] = await ethers.getSigners();

  const BBTC = await ethers.deployContract("TestBBTC");
  await BBTC.waitForDeployment();

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


  return {boss, admin, operator, player1, player2, player3, CeDeFiManager, BBTC, portfolio1, portfolio2, portfolio3};
}