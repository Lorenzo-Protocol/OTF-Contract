// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IUSD1Vault} from "./IUSD1Vault.sol";

/**
 * @title USD1PlusVault
 * @notice USD1PlusVault is a rebasing vault, which issues token USD1+, and can be exchanged to USD1 at 1:1
 */
contract USD1PlusVault is
    UUPSUpgradeable,
    ERC20Upgradeable,
    OwnableUpgradeable
{
    uint256 public constant PRECISION = 1e18;

    event MintUsd1Plus(address indexed to, uint256 sharesAmount);
    event RedeemUsd1Plus(address indexed to, uint256 sharesAmount);
    event Usd1VaultSet(address indexed usd1Vault);

    IUSD1Vault public usd1Vault;


// ------------------------------------------
    modifier onlyVault() {
        require(msg.sender == address(usd1Vault), "only vault can call");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _owner,
        address _susd1Vault
    ) public initializer {
        require(_owner != address(0), "invalid owner");
        require(_susd1Vault != address(0), "invalid usd1 vault");

        __ERC20_init("USD1+", "USD1+");
        __Ownable_init(_owner);
        usd1Vault = IUSD1Vault(_susd1Vault);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // @dev convert onePlusAmount to shares
    function convertToShares(uint256 onePlusAmount) internal view returns (uint256) {
        uint128 settlementPeriod = usd1Vault.settlementPeriod();
        uint256 nav = usd1Vault.getUnitNav(settlementPeriod);
        return onePlusAmount * PRECISION / nav;
    }

    // @dev convert shares to onePlusAmount
    function convertToOnePlus(uint256 shares) internal view returns (uint256) {
        uint128 settlementPeriod = usd1Vault.settlementPeriod();
        uint256 nav = usd1Vault.getUnitNav(settlementPeriod);
        return shares * nav / PRECISION;
    }

    // @dev get the total pooled underlying amount
    function totalPooledUnderlying() public view returns (uint256) {
        uint128 settlementPeriod = usd1Vault.settlementPeriod();
        uint256 nav = usd1Vault.getUnitNav(settlementPeriod);
        uint256 totalShares = super.totalSupply();
        return nav * totalShares / PRECISION;
    }

    // @dev get the balance of the account in USD1+
    function balanceOf(address account)
        public
        view
        override(ERC20Upgradeable)
        returns (uint256)
    {
        uint256 shares = super.balanceOf(account);
        uint128 settlementPeriod = usd1Vault.settlementPeriod();
        uint256 nav = usd1Vault.getUnitNav(settlementPeriod);
        return shares * nav / PRECISION;
    }

    // @dev transfer onePlusAmount to the target address, internally convert to shares and transfer
    function transfer(address to, uint256 onePlusAmount) public override(ERC20Upgradeable) returns (bool) {
        uint256 shares = convertToShares(onePlusAmount);
        return super.transfer(to,shares);
    }

    // @dev transferFrom onePlusAmount from the source address to the target address, internally convert to shares and transfer
    function transferFrom(address from, address to, uint256 onePlusAmount) public override(ERC20Upgradeable) returns (bool) {
        uint256 shares = convertToShares(onePlusAmount);
        return super.transferFrom(from, to, shares);
    }

    // @dev approve onePlusAmount to the target address, internally convert to shares and approve
    function approve(address spender, uint256 onePlusAmount) public override(ERC20Upgradeable) returns (bool) {
        uint256 shares = convertToShares(onePlusAmount);
        return super.approve(spender, shares);
    }

    // @dev get the allowance of the owner for the spender, internally convert to onePlusAmount
    function allowance(address owner, address spender) public view override(ERC20Upgradeable) returns (uint256) {
        uint256 shares = super.allowance(owner, spender);
        return convertToOnePlus(shares);
    }

    // @dev set the usd1 vault address
    function setUsd1Vault(address _usd1Vault) public onlyOwner {
        require(_usd1Vault != address(0), "invalid usd1 vault");
        usd1Vault = IUSD1Vault(_usd1Vault);
        emit Usd1VaultSet(_usd1Vault);
    }

    // @dev issue USD1+ to the target address,
    // users call the `usd1Vault.swap` to exchange sUSD1 to USD1+
    function mint(address to, uint256 sharesAmount) public onlyVault {
       _mint(to, sharesAmount);
       emit MintUsd1Plus(to, sharesAmount);
    }

    // @dev redeem USD1+ to the target address
    // users call the `usd1Vault.swapBack` to exchange USD1+ to sUSD1
    function redeem(address to, uint256 onePlusAmount) public {
        uint256 sharesAmount = convertToShares(onePlusAmount);
        _burn(msg.sender, sharesAmount);

        usd1Vault.swapToSusd1(to, sharesAmount);

        emit RedeemUsd1Plus(to, onePlusAmount);
    }
}
