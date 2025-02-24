import {
  time,
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { preDeploy } from "./common";

const Precesion = ethers.parseEther("1");

describe("CeDeFiManager", function () {
  it("create Vault", async function () {
    const {admin, CeDeFiManager, BBTC, player1, portfolio1, portfolio2, portfolio3} = await loadFixture(preDeploy);

    const minDepositAmount = ethers.parseEther("1");
    const minWithdrawAmount = ethers.parseEther("0.5");
    const pp1 = ethers.parseEther("0.2");
    const pp2 = ethers.parseEther("0.3");
    const pp3 = ethers.parseEther("0.5");

    await CeDeFiManager.connect(admin).addPortfolios([portfolio1.address, portfolio2.address, portfolio3.address]);

    await CeDeFiManager.connect(admin).createVault(
      1,  // yield type 1
      "Fin BTC",
      "finBTC",
      BBTC.target,
      minDepositAmount,
      minWithdrawAmount,
      [portfolio1.address, portfolio2.address, portfolio3.address],
      [pp1, pp2, pp3]
    );

    await BBTC.mint(player1.address, ethers.parseEther("1000"));

    const vaultAddress= await CeDeFiManager.getVault(0);
    const finBTCVault = await ethers.getContractAt("CustodyVault", vaultAddress);
    await BBTC.connect(player1).approve(finBTCVault.target, ethers.parseEther("1000"));

    const depositAmount = ethers.parseEther("100");
    let t = await finBTCVault.connect(player1).deposit(depositAmount);
    await t.wait();

    const pp1Balance = await BBTC.balanceOf(portfolio1.address);
    const pp2Balance = await BBTC.balanceOf(portfolio2.address);
    const pp3Balance = await BBTC.balanceOf(portfolio3.address);

    expect(pp1Balance).to.equal(depositAmount * pp1 / Precesion);
    expect(pp2Balance).to.equal(depositAmount * pp2 / Precesion);
    expect(pp3Balance).to.equal(depositAmount * pp3 / Precesion);

    const finBTCBalance = await finBTCVault.balanceOf(player1.address);
    expect(finBTCBalance).to.equal(depositAmount);

    await time.increase(86400 * 30);

    // to withdraw
    const requestId = await finBTCVault.settlementPeriod();
    const withdrawSharesAmount = ethers.parseEther("50");
    await finBTCVault.connect(player1).requestWithdraw(withdrawSharesAmount);

    const rawTotalFinBTC = await finBTCVault.totalSupply();
    const tShares = await finBTCVault.withdrewRequests(player1.address, requestId);
    expect(withdrawSharesAmount).to.equal(tShares[0]);
    expect(requestId).to.equal(tShares[1]);

    // set unit nav
    const setUnitNavData = finBTCVault.interface.encodeFunctionData(
      'setUnitNav',
      [ethers.parseEther("1.1")]
    );

    await CeDeFiManager.connect(admin).executeCommand(vaultAddress, setUnitNavData);
    const totalFinBTC = await finBTCVault.totalSupply();
    expect(totalFinBTC).to.equal(rawTotalFinBTC - withdrawSharesAmount);
    expect(2n).to.equal(await finBTCVault.settlementPeriod());

    // rebalance underlying asset offline
    await BBTC.mint(finBTCVault.target, ethers.parseEther("100"));

    // withdraw
    const p1balanceBefore = await BBTC.balanceOf(player1.address);
    const p1finBtcBalanceBefore = await finBTCVault.balanceOf(player1.address);
    await finBTCVault.connect(player1).withdraw(requestId);
    const p1balanceAfter = await BBTC.balanceOf(player1.address);
    const p1finBtcBalanceAfter = await finBTCVault.balanceOf(player1.address);

    const increaseAmount = withdrawSharesAmount * 11n/ 10n;
    expect(p1balanceAfter - p1balanceBefore).to.equal(increaseAmount);
    expect(p1finBtcBalanceBefore - p1finBtcBalanceAfter).to.equal(withdrawSharesAmount);

    const finBTCSupplyLatest = await finBTCVault.totalSupply();
    expect(finBTCSupplyLatest).to.equal(totalFinBTC); // withdraw op don't impact the total supply of finBTC
  });


});
