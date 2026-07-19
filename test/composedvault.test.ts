import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { preDeploy } from "./common";

const ONE = ethers.parseEther("1");

describe("ComposedVault", function () {
  async function deployComposedFixture() {
    const ctx = await preDeploy();
    const {
      admin,
      player1,
      player2,
      CeDeFiManager,
      BBTC,
      portfolio1,
      portfolio2,
      portfolio3,
    } = ctx;

    await CeDeFiManager.connect(admin).addPortfolios([
      portfolio1.address,
      portfolio2.address,
      portfolio3.address,
    ]);

    const implementation = await ethers.deployContract("SimpleVault");
    await implementation.waitForDeployment();

    const minDepositAmount = ethers.parseEther("1");
    const minWithdrawAmount = ethers.parseEther("0.01");
    const pp1 = ethers.parseEther("0.2");
    const pp2 = ethers.parseEther("0.3");
    const pp3 = ethers.parseEther("0.5");

    await CeDeFiManager.connect(admin).createVault(
      {
        yieldType: 1,
        name: "Child Vault A",
        symbol: "cVA",
        underlying: BBTC.target,
        minDepositAmount,
        minWithdrawAmount,
        portfolios: [portfolio1.address, portfolio2.address, portfolio3.address],
        portfolioWeights: [pp1, pp2, pp3],
      },
      implementation.target
    );

    await CeDeFiManager.connect(admin).createVault(
      {
        yieldType: 1,
        name: "Child Vault B",
        symbol: "cVB",
        underlying: BBTC.target,
        minDepositAmount,
        minWithdrawAmount,
        portfolios: [portfolio1.address, portfolio2.address, portfolio3.address],
        portfolioWeights: [pp1, pp2, pp3],
      },
      implementation.target
    );

    const vaultAAddr = await CeDeFiManager.getVault(0);
    const vaultBAddr = await CeDeFiManager.getVault(1);
    const vaultA = await ethers.getContractAt("SimpleVault", vaultAAddr);
    const vaultB = await ethers.getContractAt("SimpleVault", vaultBAddr);

    const composedImpl = await ethers.deployContract("ComposedVaultHarness");
    await composedImpl.waitForDeployment();

    const initData = composedImpl.interface.encodeFunctionData("initialize", [
      "Composed BTC",
      "cBTC",
      admin.address,
    ]);
    const composedProxy = await ethers.deployContract("ERC1967Proxy", [
      composedImpl.target,
      initData,
    ]);
    await composedProxy.waitForDeployment();

    const composed = await ethers.getContractAt(
      "ComposedVaultHarness",
      composedProxy.target
    );

    await composed.connect(admin).setUnderlying(BBTC.target);
    await composed.connect(admin).setVaults([
      { vault: vaultAAddr, weight: ethers.parseEther("0.6") },
      { vault: vaultBAddr, weight: ethers.parseEther("0.4") },
    ]);
    await composed.connect(admin).setMinDepositAmount(minDepositAmount);

    await BBTC.mint(player1.address, ethers.parseEther("1000"));
    await BBTC.mint(player2.address, ethers.parseEther("1000"));
    await BBTC.connect(player1).approve(
      composed.target,
      ethers.parseEther("1000")
    );
    await BBTC.connect(player2).approve(
      composed.target,
      ethers.parseEther("1000")
    );

    return {
      ...ctx,
      composed,
      vaultA,
      vaultB,
      vaultAAddr,
      vaultBAddr,
      implementation,
    };
  }

  async function setUnitNav(
    CeDeFiManager: any,
    admin: any,
    vault: any,
    unitNav: bigint
  ) {
    const data = vault.interface.encodeFunctionData("setUnitNav", [unitNav]);
    await CeDeFiManager.connect(admin).executeCommand(vault.target, data);
  }

  /** SimpleVault requires requestId + 1 < settlementPeriod, i.e. two settlements. */
  async function settleChildVaults(
    CeDeFiManager: any,
    admin: any,
    vaults: any[],
    unitNav: bigint,
    fundAmount: bigint,
    underlying: any
  ) {
    for (const vault of vaults) {
      await setUnitNav(CeDeFiManager, admin, vault, unitNav);
    }
    for (const vault of vaults) {
      await underlying.mint(vault.target, fundAmount);
      await setUnitNav(CeDeFiManager, admin, vault, unitNav);
    }
  }

  function parseWithdrawRequested(composed: any, receipt: any) {
    const events =
      receipt.logs
        .map((log: any) => {
          try {
            return composed.interface.parseLog(log);
          } catch {
            return null;
          }
        })
        .filter((e: any) => e && e.name === "WithdrawRequested") ?? [];
    expect(events.length).to.be.greaterThan(0);
    const ev = events[0];
    // Copy out of ethers Result (frozen) so contract calls can encode args.
    return {
      shares: ev.args.shares as bigint,
      vaults: [...ev.args.vaults] as string[],
      reqIds: [...ev.args.reqIds] as bigint[],
    };
  }

  it("deposit splits by weight and mints shares at pre-deposit NAV", async function () {
    const { composed, vaultA, vaultB, player1, BBTC } =
      await loadFixture(deployComposedFixture);

    expect(await composed.getUnitNav()).to.equal(ONE);

    const amount = ethers.parseEther("100");
    await composed.connect(player1).deposit(BBTC.target, amount);

    expect(await composed.balanceOf(player1.address)).to.equal(amount);
    expect(await composed.totalSupply()).to.equal(amount);

    // Child vaults mint shares 1:1 at period-1 NAV (= 1e18 for 18-decimal underlying)
    expect(await vaultA.balanceOf(composed.target)).to.equal(
      ethers.parseEther("60")
    );
    expect(await vaultB.balanceOf(composed.target)).to.equal(
      ethers.parseEther("40")
    );

    expect(await composed.totalAssets()).to.equal(amount);
    expect(await composed.getUnitNav()).to.equal(ONE);
  });

  it("rejects wrong deposit token and deposit below min", async function () {
    const { composed, player1, BBTC, USDT, admin } =
      await loadFixture(deployComposedFixture);

    await USDT.mint(player1.address, ethers.parseEther("100"));
    await USDT.connect(player1).approve(
      composed.target,
      ethers.parseEther("100")
    );

    await expect(
      composed.connect(player1).deposit(USDT.target, ethers.parseEther("100"))
    ).to.be.revertedWith("invalid deposit token");

    await expect(
      composed.connect(player1).deposit(BBTC.target, ethers.parseEther("0.5"))
    ).to.be.revertedWith("lt min deposit amount");

    await composed.connect(admin).pause();
    await expect(
      composed.connect(player1).deposit(BBTC.target, ethers.parseEther("10"))
    ).to.be.revertedWithCustomError(composed, "EnforcedPause");
  });

  it("setVaults validates weights and blocks when claims pending", async function () {
    const {
      composed,
      admin,
      player1,
      BBTC,
      vaultAAddr,
      vaultBAddr,
      CeDeFiManager,
      vaultA,
      vaultB,
    } = await loadFixture(deployComposedFixture);

    await expect(
      composed.connect(admin).setVaults([
        { vault: vaultAAddr, weight: ethers.parseEther("0.5") },
        { vault: vaultBAddr, weight: ethers.parseEther("0.4") },
      ])
    ).to.be.revertedWith("total weight must be ONE");

    await composed.connect(player1).deposit(BBTC.target, ethers.parseEther("100"));
    await expect(
      composed.connect(admin).setVaults([
        { vault: vaultAAddr, weight: ethers.parseEther("0.6") },
        { vault: vaultBAddr, weight: ethers.parseEther("0.4") },
      ])
    ).to.be.revertedWith("non-zero supply");

    const tx = await composed
      .connect(player1)
      .requestWithdraw(ethers.parseEther("100"));
    const receipt = await tx.wait();
    const { vaults, reqIds } = parseWithdrawRequested(composed, receipt);

    // supply burned to 0, but claims still pending
    expect(await composed.totalSupply()).to.equal(0n);
    expect(await composed.pendingClaimCount()).to.equal(2n);
    await expect(
      composed.connect(admin).setVaults([
        { vault: vaultAAddr, weight: ethers.parseEther("0.6") },
        { vault: vaultBAddr, weight: ethers.parseEther("0.4") },
      ])
    ).to.be.revertedWithCustomError(composed, "PendingWithdrawClaims");

    await settleChildVaults(
      CeDeFiManager,
      admin,
      [vaultA, vaultB],
      ONE,
      ethers.parseEther("100"),
      BBTC
    );
    await composed.connect(player1).withdraw(vaults, reqIds);
    expect(await composed.pendingClaimCount()).to.equal(0n);

    await composed.connect(admin).setVaults([
      { vault: vaultAAddr, weight: ethers.parseEther("0.5") },
      { vault: vaultBAddr, weight: ethers.parseEther("0.5") },
    ]);
    const cfg0 = await composed.vaults(0);
    expect(cfg0.weight).to.equal(ethers.parseEther("0.5"));
  });

  it("single user full redeem: requestWithdraw then withdraw", async function () {
    const {
      composed,
      player1,
      BBTC,
      admin,
      CeDeFiManager,
      vaultA,
      vaultB,
    } = await loadFixture(deployComposedFixture);

    const amount = ethers.parseEther("100");
    await composed.connect(player1).deposit(BBTC.target, amount);

    const before = await BBTC.balanceOf(player1.address);
    const tx = await composed.connect(player1).requestWithdraw(amount);
    const receipt = await tx.wait();
    const { vaults, reqIds } = parseWithdrawRequested(composed, receipt);

    expect(await composed.balanceOf(player1.address)).to.equal(0n);
    expect(await composed.totalAssets()).to.equal(0n);

    await settleChildVaults(
      CeDeFiManager,
      admin,
      [vaultA, vaultB],
      ONE,
      amount,
      BBTC
    );

    await composed.connect(player1).withdraw(vaults, reqIds);
    const after = await BBTC.balanceOf(player1.address);

    expect(after - before).to.equal(amount);
    expect(await composed.pendingClaimCount()).to.equal(0n);
    expect(await composed.periodPulled(vaults[0], reqIds[0])).to.equal(true);
    expect(await composed.periodPulled(vaults[1], reqIds[1])).to.equal(true);
  });

  it("two users same period: first pull, second claims pro-rata", async function () {
    const {
      composed,
      player1,
      player2,
      BBTC,
      admin,
      CeDeFiManager,
      vaultA,
      vaultB,
      vaultAAddr,
      vaultBAddr,
    } = await loadFixture(deployComposedFixture);

    const amount = ethers.parseEther("100");
    await composed.connect(player1).deposit(BBTC.target, amount);
    await composed.connect(player2).deposit(BBTC.target, amount);

    const tx1 = await composed
      .connect(player1)
      .requestWithdraw(ethers.parseEther("50"));
    const r1 = parseWithdrawRequested(composed, await tx1.wait());

    const tx2 = await composed
      .connect(player2)
      .requestWithdraw(ethers.parseEther("50"));
    const r2 = parseWithdrawRequested(composed, await tx2.wait());

    // Same child period for both users (merged on SimpleVault)
    expect(r1.reqIds[0]).to.equal(r2.reqIds[0]);
    expect(r1.reqIds[1]).to.equal(r2.reqIds[1]);

    const totalA = await composed.totalRequestShares(vaultAAddr, r1.reqIds[0]);
    const user1A = await composed.userRequestShares(
      player1.address,
      vaultAAddr,
      r1.reqIds[0]
    );
    const user2A = await composed.userRequestShares(
      player2.address,
      vaultAAddr,
      r2.reqIds[0]
    );
    expect(user1A + user2A).to.equal(totalA);

    // Fund enough for merged redeem on both children
    await settleChildVaults(
      CeDeFiManager,
      admin,
      [vaultA, vaultB],
      ONE,
      ethers.parseEther("200"),
      BBTC
    );

    const p1Before = await BBTC.balanceOf(player1.address);
    await composed.connect(player1).withdraw(r1.vaults, r1.reqIds);
    const p1Got = (await BBTC.balanceOf(player1.address)) - p1Before;

    expect(await composed.periodPulled(vaultAAddr, r1.reqIds[0])).to.equal(true);
    const pulledA = await composed.totalPulledUnderlying(
      vaultAAddr,
      r1.reqIds[0]
    );
    expect(pulledA).to.be.gt(0n);

    const p2Before = await BBTC.balanceOf(player2.address);
    await composed.connect(player2).withdraw(r2.vaults, r2.reqIds);
    const p2Got = (await BBTC.balanceOf(player2.address)) - p2Before;

    // Equal redeem shares → equal underlying (NAV=1)
    expect(p1Got).to.equal(p2Got);
    expect(p1Got).to.equal(ethers.parseEther("50"));

    // Second withdraw must not re-pull (same pulled amount)
    expect(await composed.totalPulledUnderlying(vaultAAddr, r1.reqIds[0])).to.equal(
      pulledA
    );
    expect(await composed.pendingClaimCount()).to.equal(0n);

    // Remaining composed supply still held by both users
    expect(await composed.balanceOf(player1.address)).to.equal(
      ethers.parseEther("50")
    );
    expect(await composed.balanceOf(player2.address)).to.equal(
      ethers.parseEther("50")
    );
    expect(vaultBAddr).to.equal(r1.vaults[1]);
  });

  it("pending redeem excludes child shares from NAV", async function () {
    const { composed, player1, player2, BBTC } =
      await loadFixture(deployComposedFixture);

    await composed.connect(player1).deposit(BBTC.target, ethers.parseEther("100"));
    await composed.connect(player2).deposit(BBTC.target, ethers.parseEther("100"));

    expect(await composed.totalAssets()).to.equal(ethers.parseEther("200"));

    await composed.connect(player1).requestWithdraw(ethers.parseEther("100"));

    // Only player2's free assets remain in NAV
    expect(await composed.totalSupply()).to.equal(ethers.parseEther("100"));
    expect(await composed.totalAssets()).to.be.closeTo(
      ethers.parseEther("100"),
      2n
    );
    expect(await composed.getUnitNav()).to.be.closeTo(ONE, 2n);
  });

  it("second depositor mints against pre-deposit NAV", async function () {
    const { composed, player1, player2, BBTC, admin, CeDeFiManager, vaultA, vaultB } =
      await loadFixture(deployComposedFixture);

    await composed.connect(player1).deposit(BBTC.target, ethers.parseEther("100"));

    // Grow child NAV to 1.1, fund portfolios side by minting into vaults for accounting consistency
    await setUnitNav(CeDeFiManager, admin, vaultA, ethers.parseEther("1.1"));
    await setUnitNav(CeDeFiManager, admin, vaultB, ethers.parseEther("1.1"));

    const nav = await composed.getUnitNav();
    expect(nav).to.equal(ethers.parseEther("1.1"));

    const deposit2 = ethers.parseEther("110");
    await composed.connect(player2).deposit(BBTC.target, deposit2);

    // shares = amount * 1e18 / nav = 110e18 * 1e18 / 1.1e18 = 100e18
    expect(await composed.balanceOf(player2.address)).to.equal(
      ethers.parseEther("100")
    );
  });
});
