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

it("work flow", async function () {
    const {admin, CeDeFiManager, USD1, USDT, USDC, player1, player2, player3, portfolio1, signer1} = AllContracts;


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
    await CeDeFiManager.connect(admin).setInvokableVaultsFuncs([
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

    // set the role
    const MINTER_ROLE = await susd1Vault.MINTER_ROLE();
    const BURNER_ROLE = await susd1Vault.BURNER_ROLE();
    let setRole = susd1Vault.interface.encodeFunctionData(
      'setRole',
      [MINTER_ROLE, player2.address, true],
    );
    await CeDeFiManager.connect(admin).executeCommand(vaultAddress, setRole);
    setRole = susd1Vault.interface.encodeFunctionData(
      'setRole',
      [BURNER_ROLE, player3.address, true],
    );
    await CeDeFiManager.connect(admin).executeCommand(vaultAddress, setRole);

    const minterRole = await susd1Vault.roles(player2.address);
    const burnerRole = await susd1Vault.roles(player3.address);
    expect(minterRole).to.equal(0x01);
    expect(burnerRole).to.equal(0x02);

    setRole = susd1Vault.interface.encodeFunctionData(
      'setRole',
      [MINTER_ROLE, player3.address, true],
    );
    await CeDeFiManager.connect(admin).executeCommand(vaultAddress, setRole);

    const minterBurnerRole = await susd1Vault.roles(player3.address);
    expect(minterBurnerRole).to.equal(0x03);

    // minter mint
    await susd1Vault.connect(player2).mint(player1.address, ethers.parseEther("100"));
    expect(await susd1Vault.balanceOf(player1.address)).to.equal(ethers.parseEther("100"));

    // burner burn
    await susd1Vault.connect(player3).burnFrom(player1.address, ethers.parseEther("50"));
    expect(await susd1Vault.balanceOf(player1.address)).to.equal(ethers.parseEther("50"));

    await expect(
      susd1Vault.connect(player2).burnFrom(player1.address, ethers.parseEther("50"))
    ).to.be.revertedWith("burner only");

    await susd1Vault.connect(player1).burn(ethers.parseEther("50"));
    expect(await susd1Vault.balanceOf(player1.address)).to.equal(ethers.parseEther("0"));

    setRole = susd1Vault.interface.encodeFunctionData(
      'setRole',
      [MINTER_ROLE, player3.address, false],
    );
    await CeDeFiManager.connect(admin).executeCommand(vaultAddress, setRole);
    const newMinterRole = await susd1Vault.roles(player3.address);
    expect(newMinterRole).to.equal(0x02);


    await expect(
      susd1Vault.connect(player3).mint(player1.address, ethers.parseEther("100"))
    ).to.be.revertedWith("minter only");

  });


});
