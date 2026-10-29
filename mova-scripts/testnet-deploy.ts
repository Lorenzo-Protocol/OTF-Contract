import { ethers } from "hardhat";
/**
 {
      "address": "0x7442Fd66DD90629130f585d28B5C6Daf81EE595e"
    }
 */

const portfolio1 = ["0x7442Fd66DD90629130f585d28B5C6Daf81EE595e"];
const weight1 = [ethers.parseEther("1")];
const main = async () => {
  const [deployer] = await ethers.getSigners();

  const USD1 = await ethers.deployContract("TestToken", ["TESTUSD1", "USD1"]);
  await USD1.waitForDeployment();

  console.log("USD1 deployed to", await USD1.getAddress());

  const USDT = await ethers.deployContract("TestToken", ["TESTUSDT", "USDT"]);
  await USDT.waitForDeployment();

  console.log("USDT deployed to", await USDT.getAddress());

  const USDC = await ethers.deployContract("TestToken", ["TESTUSDC", "USDC"]);
  await USDC.waitForDeployment();

  console.log("USDC deployed to", await USDC.getAddress());

  // deploy SimpleVault A and initialize it with USDT
  const SimpleVaultAImpl = await ethers.deployContract("SimpleVault");
  await SimpleVaultAImpl.waitForDeployment();

  console.log("SimpleVaultAImpl deployed to", await SimpleVaultAImpl.getAddress());

  const saInitData = SimpleVaultAImpl.interface.encodeFunctionData("initialize", [
    "TESTSimpleVaultA",
    "SVA",
    deployer.address // cedefi manager
  ]);

  const saProxy = await ethers.deployContract("ERC1967Proxy", [SimpleVaultAImpl.target, saInitData]);
  await saProxy.waitForDeployment();

  console.log("saProxy deployed to", await saProxy.getAddress());
  const SaVault = await ethers.getContractAt("SimpleVault", saProxy.target);
  let tx = await SaVault.connect(deployer).setUnderlying(USD1.target);
  await tx.wait();
  console.log("SaVault set underlying to", tx.hash);

  tx = await SaVault.connect(deployer).updatePortfolios(portfolio1, weight1);
  await tx.wait();
  console.log("SaVault set portfolio to", tx.hash);

  // deploy SimpleVault B and initialize it with USDT
  const SimpleVaultBImpl = await ethers.deployContract("SimpleVault");
  await SimpleVaultBImpl.waitForDeployment();

  console.log("SimpleVaultBImpl deployed to", await SimpleVaultBImpl.getAddress());

  const sbInitData = SimpleVaultBImpl.interface.encodeFunctionData("initialize", [
    "TESTSimpleVaultB",
    "SBV",
    deployer.address
  ]);

  const sbProxy = await ethers.deployContract("ERC1967Proxy", [SimpleVaultBImpl.target, sbInitData]);
  await sbProxy.waitForDeployment();

  console.log("sbProxy deployed to", await sbProxy.getAddress());
  const SbVault = await ethers.getContractAt("SimpleVault", sbProxy.target);
  tx = await SbVault.connect(deployer).setUnderlying(USD1.target);
  await tx.wait();
  console.log("SbVault set underlying to", tx.hash);

  tx = await SbVault.connect(deployer).updatePortfolios(portfolio1, weight1);
  await tx.wait();
  console.log("SbVault set portfolio to", tx.hash);

  // deploy ComposedVault and initialize it with SaVault and SbVault
  const ComposedVaultImpl = await ethers.deployContract("ComposedVault");
  await ComposedVaultImpl.waitForDeployment();

  console.log("ComposedVaultImpl deployed to", await ComposedVaultImpl.getAddress());

  const cvInitData = ComposedVaultImpl.interface.encodeFunctionData("initialize", [
    "TESTComposedVault",
    "cbUSDT-USDC",
    deployer.address
  ]);

  const cvProxy = await ethers.deployContract("ERC1967Proxy", [ComposedVaultImpl.target, cvInitData]);
  await cvProxy.waitForDeployment();

  console.log("cvProxy deployed to", await cvProxy.getAddress());
  const CvVault = await ethers.getContractAt("ComposedVault", cvProxy.target);
  tx = await CvVault.connect(deployer).setUnderlying(USD1.target);
  await tx.wait();
  console.log("CvVault set underlying to", tx.hash);

  // set SaVault and SbVault to ComposedVault
  tx = await CvVault.connect(deployer).setVaults([
    { vault: SaVault.target, weight: ethers.parseEther("0.8") },
    { vault: SbVault.target, weight: ethers.parseEther("0.2") }
  ]);
  await tx.wait();
  console.log("CvVault set vaults to", tx.hash);
}

main();