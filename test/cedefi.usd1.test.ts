import {
  time,
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { preDeploy } from "./common";
import { TypedDataDomain } from "ethers";

const Precesion = ethers.parseEther("1");

describe("ERC20 Vault", function () {
let AllContracts: any;

this.beforeEach(async function () {
  AllContracts= await loadFixture(preDeploy);

});

// this.afterEach(async function () {

// });

async function getClaimSinature(operator: any, contract: string, period: bigint, user: string, sharesAmount: bigint, nonce: bigint) {
  const domain: TypedDataDomain = {
    name: "USD1Vault",
    version: "1.0",
    verifyingContract:contract,
    chainId: (await ethers.provider.getNetwork()).chainId
  };
// uint128 period,address user,uint256 sharesAmount
  const types = {
    "ConfirmShare":[
      {name: "period", type: "uint128"},
      {name: "user", type: "address"},
      {name: "sharesAmount", type: "uint256"},
      {name: "nonce", type: "uint256"},
    ]
  };

  const values = {
    period,
    user,
    sharesAmount,
    nonce,
  };

  const signature = await operator.signTypedData(domain, types, values);
  return signature;
}

it("work flow", async function () {
    const {admin, CeDeFiManager, USD1, player1, portfolio1, signer1} = AllContracts;


    const minDepositAmount = ethers.parseEther("50");
    const minWithdrawAmount = ethers.parseEther("50");
    const pp1 = ethers.parseEther("1.0");

    await CeDeFiManager.connect(admin).addPortfolios([portfolio1.address]);
    const implementation = await ethers.deployContract("USD1Vault");
    await implementation.waitForDeployment();

    await CeDeFiManager.connect(admin).createVault(
      {
        yieldType: 1,  // yield type 1
        name: "sUSD1+",
        symbol: "sUSD1+",
        underlying: USD1.target,
        minDepositAmount,
        minWithdrawAmount,
        portfolios: [portfolio1.address],
        portfolioWeights: [pp1]
      },
      implementation.target
    );

    await USD1.mint(player1.address, ethers.parseEther("1000"));

    const vaultAddress= await CeDeFiManager.getVault(0);
    const usd1Vault = await ethers.getContractAt("USD1Vault", vaultAddress);
    // 增加setSigner函数
    await CeDeFiManager.connect(admin).addAllowedVaultsFuncs([
      usd1Vault.interface.getFunction('setSigner')!.selector,
    ], [true]);

    // set unit nav
    const setSigners = usd1Vault.interface.encodeFunctionData(
      'setSigner',
      [[signer1.address], [true]]
    );
    await CeDeFiManager.connect(admin).executeCommand(vaultAddress, setSigners);

    await USD1.connect(player1).approve(usd1Vault.target, ethers.parseEther("1000"));

    const depositAmount = ethers.parseEther("100");
    let t = await usd1Vault.connect(player1).deposit(depositAmount);
    await t.wait();

    const pp1Balance = await USD1.balanceOf(portfolio1.address);

    expect(pp1Balance).to.equal(depositAmount * pp1 / Precesion);

    const usd1Balance = await USD1.balanceOf(portfolio1.address);
    expect(usd1Balance).to.equal(depositAmount);

    // 尚未确定份额，所以为0
    expect(await usd1Vault.balanceOf(player1.address)).to.equal(0);

    const confirmNonce = await usd1Vault.confirmNonce(player1.address);
    const signature = await getClaimSinature(signer1, usd1Vault.target as string, 1n, player1.address, depositAmount, confirmNonce);
    await usd1Vault.connect(player1).confirmShare(1n, depositAmount, signature);

    // 现在份额为100
    expect(await usd1Vault.balanceOf(player1.address)).to.equal(depositAmount);

    await time.increase(86400 * 30);

    // to withdraw
    const requestId = await usd1Vault.settlementPeriod();
    const withdrawSharesAmount = ethers.parseEther("50");
    await usd1Vault.connect(player1).requestWithdraw(withdrawSharesAmount);

    const rawTotalUSD1 = await usd1Vault.totalSupply();
    const tShares = await usd1Vault.withdrewRequests(player1.address, requestId);
    expect(withdrawSharesAmount).to.equal(tShares[0]);
    expect(requestId).to.equal(tShares[1]);

    // set unit nav
    const setUnitNavData = usd1Vault.interface.encodeFunctionData(
      'setUnitNav',
      [ethers.parseEther("1.1")]
    );

    await CeDeFiManager.connect(admin).executeCommand(vaultAddress, setUnitNavData);
    const totalUSD1 = await usd1Vault.totalSupply();
    expect(totalUSD1).to.equal(rawTotalUSD1 - withdrawSharesAmount);
    expect(2n).to.equal(await usd1Vault.settlementPeriod());

    // rebalance underlying asset offline
    await USD1.mint(usd1Vault.target, ethers.parseEther("100"));

    // withdraw
    const p1balanceBefore = await USD1.balanceOf(player1.address);
    const p1usd1BalanceBefore = await usd1Vault.balanceOf(player1.address);
    await usd1Vault.connect(player1).withdraw(requestId);
    const p1balanceAfter = await USD1.balanceOf(player1.address);
    const p1usd1BalanceAfter = await usd1Vault.balanceOf(player1.address);

    const increaseAmount = withdrawSharesAmount * 11n/ 10n;
    expect(p1balanceAfter - p1balanceBefore).to.equal(increaseAmount);
    expect(p1usd1BalanceBefore - p1usd1BalanceAfter).to.equal(withdrawSharesAmount);

    const usd1SupplyLatest = await usd1Vault.totalSupply();
    expect(usd1SupplyLatest).to.equal(totalUSD1); // withdraw op don't impact the total supply of finBTC
  });


});
