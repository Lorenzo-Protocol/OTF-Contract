import {
  time,
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { preDeploy, getClaimSinature } from "./common";

const Precesion = ethers.parseEther("1");
const NATIVE_TOKEN = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";

describe("BNB Vault", function () {
let AllContracts: any;

this.beforeEach(async function () {
  AllContracts= await loadFixture(preDeploy);


});

it("create Vault", async function () {
    const {admin, CeDeFiManager, player1, portfolio1, portfolio2, portfolio3, signer1} = AllContracts;
    await ethers.provider.send("hardhat_setBalance", [portfolio1.address, "0x0"]);
    await ethers.provider.send("hardhat_setBalance", [portfolio2.address, "0x0"]);
    await ethers.provider.send("hardhat_setBalance", [portfolio3.address, "0x0"]);

    const minDepositAmount = ethers.parseEther("0.02");
    const minWithdrawAmount = ethers.parseEther("0.5");
    const pp1 = ethers.parseEther("1.0");

    await CeDeFiManager.connect(admin).addPortfolios([portfolio1.address]);
    const implementation = await ethers.deployContract("BnbPlusVault");
    await implementation.waitForDeployment();

    await CeDeFiManager.connect(admin).createVault(
      {
        yieldType: 1,  // yield type 1
        name: "BNB+",
        symbol: "BNB+",
        underlying: NATIVE_TOKEN,
        minDepositAmount,
        minWithdrawAmount,
        portfolios: [portfolio1.address],
        portfolioWeights: [pp1]
      },
      implementation.target
    );

    const vaultAddress= await CeDeFiManager.getVault(0);
    const hgBNBVault = await ethers.getContractAt("BnbPlusVault", vaultAddress);

    // set unit nav
    const setSigners = hgBNBVault.interface.encodeFunctionData(
      'setSigner',
      [[signer1.address], [true]]
    );
    await CeDeFiManager.connect(admin).executeCommand(vaultAddress, setSigners);

    const depositAmount = ethers.parseEther("1.0");
    let t = await hgBNBVault.connect(player1).deposit(NATIVE_TOKEN, depositAmount, {value: depositAmount});
    await t.wait();

    const pp1Balance = await ethers.provider.getBalance(portfolio1.address);

    expect(pp1Balance).to.equal(depositAmount * pp1 / Precesion);

    const name = "BnbPlusVault";
    const version = "1.0";
    const signature = await getClaimSinature(
      signer1,
      name,
      version,
      hgBNBVault.target as string,
      1n,
      player1.address,
      depositAmount,
      t.hash
    );
    await hgBNBVault.connect(player1).confirmShare(1n, t.hash, depositAmount, signature);

    const hgBNBBalance = await hgBNBVault.balanceOf(player1.address);
    expect(hgBNBBalance).to.equal(depositAmount);

    await time.increase(86400 * 30);

    // to withdraw
    const requestId = await hgBNBVault.settlementPeriod();
    const withdrawSharesAmount = ethers.parseEther("0.5");
    await hgBNBVault.connect(player1).requestWithdraw(withdrawSharesAmount);

    const rawTotalhgBNB = await hgBNBVault.totalSupply();
    const tShares = await hgBNBVault.withdrewRequests(player1.address, requestId);
    expect(withdrawSharesAmount).to.equal(tShares[0]);
    expect(requestId).to.equal(tShares[1]);

    // set unit nav
    const setUnitNavData = hgBNBVault.interface.encodeFunctionData(
      'setUnitNav',
      [ethers.parseEther("1.1")]
    );

    await CeDeFiManager.connect(admin).executeCommand(vaultAddress, setUnitNavData);
    const totalhgBNB = await hgBNBVault.totalSupply();
    expect(totalhgBNB).to.equal(rawTotalhgBNB - withdrawSharesAmount);
    expect(2n).to.equal(await hgBNBVault.settlementPeriod());
    // set unit nav again
    await CeDeFiManager.connect(admin).executeCommand(vaultAddress, setUnitNavData);

    // withdraw
    // rebalance the widrawing balance to vault
    await admin.sendTransaction({to: hgBNBVault.target, value: ethers.parseEther("1")});

    const p1balanceBefore = await ethers.provider.getBalance(player1.address);
    const p1hgBNBBalanceBefore = await hgBNBVault.balanceOf(player1.address);
    // execute withdraw
    await hgBNBVault.connect(player1).withdraw(requestId);
    const p1balanceAfter = await ethers.provider.getBalance(player1.address);
    const p1hgBNBBalanceAfter = await hgBNBVault.balanceOf(player1.address);

    const increaseAmount = withdrawSharesAmount * 11n/ 10n;
    expect(p1balanceAfter - p1balanceBefore - increaseAmount).to.be.lessThan(ethers.parseEther("0.0000001"));
    expect(p1hgBNBBalanceBefore - p1hgBNBBalanceAfter - withdrawSharesAmount).to.be.lessThan(ethers.parseEther("0.0000001"));

    const hgBNBSupplyLatest = await hgBNBVault.totalSupply();
    expect(hgBNBSupplyLatest).to.equal(totalhgBNB); // withdraw op don't impact the total supply of hgBNB
  });
});
