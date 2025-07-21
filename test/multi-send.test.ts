import {
  time,
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { ethers } from "hardhat";
import { preDeploy } from "./common";
import { expect } from "chai";

const receivers = (require("../debug-script/auto-mm/mainnet-2000.json") as any).accounts as any[];

const BatchSize = 250;
const TotalAmount = receivers.length;
const TotalBatches = Math.floor((TotalAmount + BatchSize) / BatchSize);

const nativeAmount = ethers.parseEther("0.00002");
const usd1Amount = ethers.parseEther("1");

function getBatchAddress(batchIdx: number, value: bigint) {
  if (batchIdx >= TotalBatches) return {address: [], amount: []};

  const startIndex = batchIdx * BatchSize;
  let endIndex = startIndex + BatchSize;
  endIndex = endIndex > TotalAmount ? TotalAmount : endIndex;

  let address = [];
  let amount = [];
  for (let i = startIndex; i < endIndex; i++) {
    address.push(receivers[i].address);
    amount.push(value);
  }
  return {address, amount};
}

describe("MultiSend", function () {

  it("multi send native token", async function () {
    const {MultiSend} = await loadFixture(preDeploy);

    for (let i = 0; i < TotalBatches; i++) {
      const {address, amount} = getBatchAddress(i, nativeAmount);

      const tx = await MultiSend.multiSendNative(address, amount, {value: nativeAmount * BigInt(address.length)});
      await tx.wait()
      console.log(`Batch ${i} : ${tx.hash}`);
    }

    for (let i = 0; i < receivers.length; i++) {
      const balance = await ethers.provider.getBalance(receivers[i].address);
      expect(balance).to.be.equal(nativeAmount);
    }
  });

  it("multi send erc20 token", async function () {
    const {MultiSend, USDT, player1} = await loadFixture(preDeploy);

    await USDT.mint(player1.address, usd1Amount * 2000n);
    await USDT.connect(player1).approve(MultiSend.target, usd1Amount * 2000n);

    for (let i = 0; i < TotalBatches; i++) {
      const {address, amount} = getBatchAddress(i, usd1Amount);

      const tx = await MultiSend.connect(player1).multiSendERC20(USDT.target, address, amount);
      await tx.wait()
      console.log(`Batch ${i} : ${tx.hash}`);
    }

    for (let i = 0; i < receivers.length; i++) {
      const balance = await USDT.balanceOf(receivers[i].address);
      expect(balance).to.be.equal(usd1Amount);
    }
  });
});
