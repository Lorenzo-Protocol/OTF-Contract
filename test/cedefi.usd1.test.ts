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

async function getClaimSinature(operator: any, contract: string, period: bigint, user: string, sharesAmount: bigint, txHash: string) {
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

async function deployUSD1PlusVault(susd1Vault: string) {
  const {admin} = AllContracts;
  const implementation = await ethers.deployContract("USD1PlusVault");
  await implementation.waitForDeployment();

  const initdata = implementation.interface.encodeFunctionData(
    'initialize',
    [
      admin.address,
      susd1Vault,
      [admin.address]
    ]
  );

  const USD1PlusVaultProxy = await ethers.deployContract("ERC1967Proxy", [implementation.target, initdata]);
  await USD1PlusVaultProxy.waitForDeployment();

  const USD1PlusVault = await ethers.getContractAt("USD1PlusVault", USD1PlusVaultProxy.target);

  return {USD1PlusVault};
}

it("work flow", async function () {
    const {admin, CeDeFiManager, USD1, USDT, USDC, player1, player2, portfolio1, signer1} = AllContracts;


    const minDepositAmount = ethers.parseEther("50");
    const minWithdrawAmount = ethers.parseEther("50");
    const pp1 = ethers.parseEther("1.0");

    await CeDeFiManager.connect(admin).addPortfolios([portfolio1.address]);
    const implementation = await ethers.deployContract("sUSD1PlusVault");
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
    await USDT.mint(player1.address, ethers.parseEther("1000"));
    await USDC.mint(player1.address, ethers.parseEther("1000"));

    const vaultAddress= await CeDeFiManager.getVault(0);
    const susd1Vault = await ethers.getContractAt("sUSD1PlusVault", vaultAddress);

    // 增加setSigner函数
    await CeDeFiManager.connect(admin).addAllowedVaultsFuncs([
      susd1Vault.interface.getFunction('setSigner')!.selector,
      susd1Vault.interface.getFunction('setUsd1PlusVault')!.selector,
      susd1Vault.interface.getFunction('setAcceptUnderlying')!.selector,
    ], [true, true, true]);

    // set unit nav
    const setSigners = susd1Vault.interface.encodeFunctionData(
      'setSigner',
      [[signer1.address], [true]]
    );
    await CeDeFiManager.connect(admin).executeCommand(vaultAddress, setSigners);

    // set the accept underlying token
    const setAcceptUnderlying = susd1Vault.interface.encodeFunctionData(
      'setAcceptUnderlying',
      [[USDT.target, USDC.target], [true, true]]
    );
    await CeDeFiManager.connect(admin).executeCommand(vaultAddress, setAcceptUnderlying);

    // set the usd1 plus vault
    const {USD1PlusVault} = await deployUSD1PlusVault(susd1Vault.target as string);

    const setUsd1PlusVault = susd1Vault.interface.encodeFunctionData(
      'setUsd1PlusVault',
      [USD1PlusVault.target]
    );
    await CeDeFiManager.connect(admin).executeCommand(vaultAddress, setUsd1PlusVault);

    await USD1.connect(player1).approve(susd1Vault.target, ethers.parseEther("1000"));
    await USDT.connect(player1).approve(susd1Vault.target, ethers.parseEther("1000"));
    await USDC.connect(player1).approve(susd1Vault.target, ethers.parseEther("1000"));

    const depositAmount = ethers.parseEther("100");
    let t = await susd1Vault.connect(player1).deposit(USD1.target, depositAmount);
    await t.wait();

    t = await susd1Vault.connect(player1).deposit(USDT.target, depositAmount);
    await t.wait();

    t = await susd1Vault.connect(player1).deposit(USDC.target, depositAmount);
    await t.wait();

    const pp1Balance = await USD1.balanceOf(portfolio1.address);

    expect(pp1Balance).to.equal(depositAmount * pp1 / Precesion);

    const usd1Balance = await USD1.balanceOf(portfolio1.address);
    expect(usd1Balance).to.equal(depositAmount);

    // 尚未确定份额，所以为0
    expect(await susd1Vault.balanceOf(player1.address)).to.equal(0);

    const signature = await getClaimSinature(signer1, susd1Vault.target as string, 1n, player1.address, 3n*depositAmount, t.hash);
    await susd1Vault.connect(player1).confirmShare(1n, t.hash, 3n*depositAmount, signature);

    // 现在份额为100 * 3, 因为deposit了3次
    expect(await susd1Vault.balanceOf(player1.address)).to.equal(3n*depositAmount);

    await time.increase(86400 * 30);

    const sharesAmount = (await susd1Vault.balanceOf(player1.address)) / 2n;
    await susd1Vault.connect(player1).swapToUsd1Plus(player1.address, sharesAmount);

    // nav 为 1, 所以100 shares 对应 100 USD1+
    expect(await USD1PlusVault.balanceOf(player1.address)).to.equal(3n*depositAmount / 2n);
    // transfer 50 USD1+ to player2
    await USD1PlusVault.connect(player1).transfer(player2.address, sharesAmount / 2n);

    expect(await USD1PlusVault.balanceOf(player2.address)).to.equal(3n*depositAmount / 4n);

    // to withdraw
    const requestId = await susd1Vault.settlementPeriod();
    const withdrawSharesAmount = await susd1Vault.balanceOf(player1.address);
    await susd1Vault.connect(player1).requestWithdraw(withdrawSharesAmount);

    const rawTotalUSD1 = await susd1Vault.totalSupply();
    const tShares = await susd1Vault.withdrewRequests(player1.address, requestId);
    expect(withdrawSharesAmount).to.equal(tShares[0]);
    expect(requestId).to.equal(tShares[1]);

    // set unit nav
    const setUnitNavData = susd1Vault.interface.encodeFunctionData(
      'setUnitNav',
      [ethers.parseEther("1.1")]
    );

    await CeDeFiManager.connect(admin).executeCommand(vaultAddress, setUnitNavData);
    const totalUSD1 = await susd1Vault.totalSupply();
    expect(totalUSD1).to.equal(rawTotalUSD1 - withdrawSharesAmount);
    expect(2n).to.equal(await susd1Vault.settlementPeriod());

    // player1和player2的USD1+份额都为 depositAmount * 1.1 / 2
    expect(await USD1PlusVault.balanceOf(player1.address)).to.equal(3n*depositAmount * 11n / 40n);
    expect(await USD1PlusVault.balanceOf(player2.address)).to.equal(3n*depositAmount * 11n / 40n);

    // player2redeem它的balance之后, 仍然应该拿到sharesAmount / 2
    const p2BalanceBefore = await USD1PlusVault.balanceOf(player2.address);
    await USD1PlusVault.connect(player2).redeem(player2.address, p2BalanceBefore);
    expect(await USD1PlusVault.balanceOf(player2.address)).to.equal(0n);
    expect(await susd1Vault.balanceOf(player2.address)).to.equal(sharesAmount / 2n);

    // rebalance underlying asset offline
    await USD1.mint(susd1Vault.target, 3n*ethers.parseEther("100"));

    // withdraw
    const p1balanceBefore = await USD1.balanceOf(player1.address);
    const p1usd1BalanceBefore = await susd1Vault.balanceOf(player1.address);
    await susd1Vault.connect(player1).withdraw(requestId);
    const p1balanceAfter = await USD1.balanceOf(player1.address);
    const p1usd1BalanceAfter = await susd1Vault.balanceOf(player1.address);

    const increaseAmount = withdrawSharesAmount * 11n/ 10n;
    expect(p1balanceAfter - p1balanceBefore).to.equal(increaseAmount);
    expect(p1usd1BalanceBefore - p1usd1BalanceAfter).to.equal(withdrawSharesAmount);

    const usd1SupplyLatest = await susd1Vault.totalSupply();
    expect(usd1SupplyLatest).to.equal(totalUSD1); // withdraw op don't impact the total supply of finBTC
  });


});
