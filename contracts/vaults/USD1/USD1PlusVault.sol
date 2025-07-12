// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IsUSD1PlusVault} from "./IsUSD1PlusVault.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

/**
 * @title USD1PlusVault
 * @notice USD1PlusVault is a rebasing vault, which issues token USD1+, and can be exchanged to USD1 at 1:1
 */
contract USD1PlusVault is
    UUPSUpgradeable,
    ERC20Upgradeable,
    AccessControlUpgradeable
{
    uint256 public constant PRECISION = 1e18;
    bytes32 public constant OWNER_ROLE = keccak256("VAULT_ROLE");
    bytes32 public constant FREEZER_ROLE = keccak256("FREEZER_ROLE");

    event MintUsd1Plus(address indexed to, uint256 sharesAmount);
    event RedeemUsd1Plus(address indexed to, uint256 sharesAmount);
    event Usd1VaultSet(address indexed susd1Vault);
    event Freeze(address indexed account, uint256 sharesAmount);
    event Unfreeze(address indexed account, uint256 sharesAmount);

    IsUSD1PlusVault public susd1Vault;

    mapping(address => uint256) public frozenShares;
// ------------------------------------------
    modifier onlyVault() {
        require(msg.sender == address(susd1Vault), "only vault can call");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _owner,
        address _susd1Vault,
        address[] memory _freezers
    ) public initializer {
        require(_owner != address(0), "invalid owner");
        require(_susd1Vault != address(0), "invalid usd1 vault");

        __ERC20_init("Lorenzo USD1+", "USD1+");
        __AccessControl_init();

        _setRoleAdmin(OWNER_ROLE, OWNER_ROLE);
        _setRoleAdmin(FREEZER_ROLE, OWNER_ROLE);

        _grantRole(OWNER_ROLE, _owner);
        _grantRole(FREEZER_ROLE, _owner);

        for (uint256 i; i < _freezers.length; i++) {
            _grantRole(FREEZER_ROLE, _freezers[i]);
        }
        susd1Vault = IsUSD1PlusVault(_susd1Vault);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(OWNER_ROLE) {}

    // @dev convert onePlusAmount to shares
    function convertToShares(uint256 onePlusAmount) internal view returns (uint256) {
        uint128 settlementPeriod = susd1Vault.settlementPeriod();
        uint256 nav = susd1Vault.getUnitNav(settlementPeriod);
        return onePlusAmount * PRECISION / nav;
    }

    // @dev convert shares to onePlusAmount
    function convertToOnePlus(uint256 shares) internal view returns (uint256) {
        uint128 settlementPeriod = susd1Vault.settlementPeriod();
        uint256 nav = susd1Vault.getUnitNav(settlementPeriod);
        return shares * nav / PRECISION;
    }

    // @dev get the total pooled underlying amount
    function totalPooledUnderlying() public view returns (uint256) {
        uint128 settlementPeriod = susd1Vault.settlementPeriod();
        uint256 nav = susd1Vault.getUnitNav(settlementPeriod);
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
        uint128 settlementPeriod = susd1Vault.settlementPeriod();
        uint256 nav = susd1Vault.getUnitNav(settlementPeriod);
        return shares * nav / PRECISION;
    }

    // @dev transfer onePlusAmount to the target address, internally convert to shares and transfer
    function transfer(address to, uint256 onePlusAmount) public override(ERC20Upgradeable) returns (bool) {
        uint256 shares = convertToShares(onePlusAmount);
        require(getUseableShares(msg.sender) >= shares, "can not transfer so much shares");
        return super.transfer(to,shares);
    }

    // @dev transferFrom onePlusAmount from the source address to the target address, internally convert to shares and transfer
    function transferFrom(address from, address to, uint256 onePlusAmount) public override(ERC20Upgradeable) returns (bool) {
        uint256 shares = convertToShares(onePlusAmount);
        require(getUseableShares(from) >= shares, "can not transfer so much shares");
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
    function setUsd1Vault(address _susd1Vault) public onlyRole(OWNER_ROLE) {
        require(_susd1Vault != address(0), "invalid usd1 vault");
        susd1Vault = IsUSD1PlusVault(_susd1Vault);
        emit Usd1VaultSet(_susd1Vault);
    }

    // @dev calculate the useable shares amount
    function getUseableShares(address account) public view returns (uint256) {
        return super.balanceOf(account) - frozenShares[account];
    }

    // @dev freeze the shares of the target address
    function freeze(address account, uint256 onePlusAmount) public onlyRole(FREEZER_ROLE) {
        require(onePlusAmount > 0, "invalid onePlusAmount");
        uint256 sharesAmount = convertToShares(onePlusAmount);
        require(sharesAmount <= getUseableShares(account), "can not freeze so much shares");

        frozenShares[account] += sharesAmount;

        emit Freeze(account, sharesAmount);
    }

    // @dev unfreeze the shares of the target address
    function unfreeze(address account, uint256 sharesAmount) public onlyRole(FREEZER_ROLE) {
        require(sharesAmount > 0, "shares amount is zero");
        require(frozenShares[account] >= sharesAmount, "can not unfreeze so much shares");

        frozenShares[account] -= sharesAmount;

        emit Unfreeze(account, sharesAmount);
    }

    // @dev issue USD1+ to the target address,
    // users call the `susd1Vault.swap` to exchange sUSD1 to USD1+
    function mint(address to, uint256 sharesAmount) public onlyVault {
       _mint(to, sharesAmount);
       emit MintUsd1Plus(to, sharesAmount);
    }

    // @dev redeem USD1+ to the target address
    // users call the `susd1Vault.swapBack` to exchange USD1+ to sUSD1
    function redeem(uint256 onePlusAmount) public {
        uint256 sharesAmount = convertToShares(onePlusAmount);
        _burn(msg.sender, sharesAmount);

        susd1Vault.swapToSusd1(msg.sender, sharesAmount);

        emit RedeemUsd1Plus(msg.sender, onePlusAmount);
    }
}
