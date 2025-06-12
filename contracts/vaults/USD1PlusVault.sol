// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {USD1Vault} from "./USD1Vault.sol";
import {Vault} from "./Vault.sol";

/**
 * @title USD1PlusVault
 * @notice USD1PlusVault is a rebasing vault, which issues token USD1+, and can be exchanged to USD1 at 1:1
 */
contract USD1PlusVault is
    USD1Vault
{
    // @dev convert onePlusAmount to shares
    function convertToShares(uint256 onePlusAmount) internal view returns (uint256) {
        uint256 nav = getUnitNav(settlementPeriod);
        return onePlusAmount * Precision / nav;
    }

    // @dev convert shares to onePlusAmount
    function convertToOnePlus(uint256 shares) internal view returns (uint256) {
        uint256 nav = getUnitNav(settlementPeriod);
        return shares * nav / Precision;
    }

    // @dev get the total pooled underlying amount
    function totalPooledUnderlying() public view returns (uint256) {
        uint256 nav = getUnitNav(settlementPeriod);
        uint256 totalShares = super.totalSupply();
        return nav * totalShares / Precision;
    }

    // @dev get the balance of the account in USD1+
    function balanceOf(address account)
        public
        view
        override(ERC20Upgradeable, IERC20)
        returns (uint256)
    {
        uint256 shares = super.balanceOf(account);
        uint256 nav = getUnitNav(settlementPeriod);
        return shares * nav / Precision;
    }

    // @dev transfer onePlusAmount to the target address, internally convert to shares and transfer
    function transfer(address to, uint256 amount) public override(Vault) returns (bool) {
        uint256 shares = convertToShares(amount);
        return super.transfer(to,shares);
    }

    // @dev transferFrom onePlusAmount from the source address to the target address, internally convert to shares and transfer
    function transferFrom(address from, address to, uint256 amount) public override(Vault) returns (bool) {
        uint256 shares = convertToShares(amount);
        return super.transferFrom(from, to, shares);
    }

    // @dev approve onePlusAmount to the target address, internally convert to shares and approve
    function approve(address spender, uint256 amount) public override(ERC20Upgradeable, IERC20) returns (bool) {
        uint256 shares = convertToShares(amount);
        return super.approve(spender, shares);
    }

    // @dev get the allowance of the owner for the spender, internally convert to onePlusAmount
    function allowance(address owner, address spender) public view override(ERC20Upgradeable, IERC20) returns (uint256) {
        uint256 shares = super.allowance(owner, spender);
        return convertToOnePlus(shares);
    }

    // @dev request to finish withdraw
    function requestWithdraw(uint256 onePlusAmount)
        public
        override(Vault)
        returns (uint128)
    {
        uint256 shares = convertToShares(onePlusAmount);
        return super.requestWithdraw(shares);
    }
}
