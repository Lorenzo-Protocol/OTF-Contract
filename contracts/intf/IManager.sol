// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;
import {YieldType} from "./IVault.sol";

interface IManager {
    event VaultCreated(address indexed vault, YieldType yieldType, string name, string symbol, address underlying, address[] portfolios, uint256[] weights);
    event FundCreated(address indexed fund, string name, string symbol, address[] vaults, uint256[] weights);

    // @dev to create a new vault
    // @param name the name of the vault
    // @param symbol the symbol of the vault
    // @param underlying the underlying token address
    // @param yieldType the yield type of the vault
    // @param portfolios the portfolio addresses
    // @param weights the portfolio weights
    function createVault(
        string calldata name,
        string calldata symbol,
        address underlying,
        YieldType yieldType,
        address[] calldata portfolios,
        uint256[] calldata weights
    ) external returns (address);

    function createFund(
        string calldata name,
        string calldata symbol,
        address[] calldata vaults,
        uint256[] calldata weights
    ) external returns (address);

    // @dev to set the unit nav of the vault, only admin or authorized roles
    // @param vault the vault address
    // @param unitNav the unit nav
    function setUnitNav(address vault, uint256 unitNav) external;

    // @dev to add a portfolio to the manager, only admin or authorized roles
    //     the vault MUST choose the portfolios from the manager
    // @param portfolio the portfolio address
    function addPortfolio(address portfolio) external;
    // @dev to remove a portfolio from the manager, only admin or authorized roles
    //     while removed, the vault can not use the portfolio any more
    // @param portfolio the portfolio address
    function removePortfolio(address portfolio) external;

    // @dev to pause the vault. only admin or authorized roles
    //    when paused, the vault can not accept deposit or withdraw
    // @param vault the vault address
    function pauseVault(address vault) external;
    // @dev to unpause the vault. only admin or authorized roles
    function unpauseVault(address vault) external;

    // @dev to pause the fund. only admin or authorized roles
    //    when paused, the fund can not accept deposit or withdraw
    // @param fund the fund address
    function pauseFund(address fund) external;
    // @dev to unpause the fund. only admin or authorized roles
    function unpauseFund(address fund) external;

    // @dev to upgrade the vault implementation
    // @param vault the vault address
    // @param newImpl the new implementation address
    // @param data the data to call the new implementation
    function upgradeVault(address vault, address newImpl, bytes calldata data) external;

    // @dev to upgrade the fund implementation
    // @param fund the fund address
    // @param newImpl the new implementation address
    // @param data the data to call the new implementation
    function upgradeFund(address fund, address newImpl, bytes calldata data) external;
}