// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {IVault, YieldType} from "./intf/IVault.sol";
import {CustodyVault} from "./vaults/CustodyVault.sol";
import {CeDeFiManagerBase} from "./CeDeFiManagerBase.sol";

import "hardhat/console.sol";

contract CeDeFiManager is UUPSUpgradeable, AccessControlUpgradeable, CeDeFiManagerBase {
    using EnumerableSet for EnumerableSet.AddressSet;

    constructor() {
        _disableInitializers();
    }

    function initialize(address boss, address admin) public initializer {
        require(boss != address(0), "CeDeFiManager: boss is zero address");
        require(admin != address(0), "CeDeFiManager: admin is zero address");

        __UUPSUpgradeable_init();
        __AccessControl_init();

        _setRoleAdmin(BOSS_ROLE, BOSS_ROLE);
        _setRoleAdmin(ADMIN_ROLE, BOSS_ROLE);
        _setRoleAdmin(OPERATOR_ROLE, ADMIN_ROLE);

        _grantRole(BOSS_ROLE, boss);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE, admin);
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyRole(BOSS_ROLE){
    }

    // @dev add profilios to the systems
    function addPortfolios(address[] memory portfolios) public onlyRole(ADMIN_ROLE) {
        uint256 len = portfolios.length;
        for (uint256 i; i < len; ) {
            _activePortfolios.add(portfolios[i]);
            unchecked { ++i; }
        }

        emit AddPortfolios(portfolios);
    }

    // @dev delete portfolio from the systems
    function deletePortfolios(address[] memory portfolios) public onlyRole(ADMIN_ROLE) {
        uint256 len = portfolios.length;
        for (uint256 i; i < len; ) {
            _activePortfolios.remove(portfolios[i]);
            unchecked { ++i; }
        }

        emit DeletePortfolios(portfolios);
    }

    // @dev manage the vaults
    function executeCommand(address vault, bytes memory data) public onlyRole(OPERATOR_ROLE) {
        require(_vaults.contains(vault), "CeDeFiManager: vault not exist");
        (bool success, bytes memory returndata) = vault.call(data);
        require(success, string(returndata));
    }

    // @dev to create a custody vault
    function createCustodyVault(
        string memory name,
        string memory symbol,
        address underlying,
        address[] memory portfolios,
        uint256[] memory portfolioWeights,
        uint256 minDepositAmount,
        uint256 minWithdrawAmount
    )
        internal
    {

        require(portfolios.length == portfolioWeights.length, "CeDeFiManager: invalid length portfolios and weights");
        uint len = portfolios.length;
        for (uint i = 0; i < len; ) {
            require(_activePortfolios.contains(portfolios[i]), "CeDeFiManager: portfolio not exists");
            unchecked { ++i; }
        }

        bytes memory data = abi.encodeWithSignature(
            "initialize(string,string,address,address[],uint256[])",
            name, symbol, underlying, portfolios, portfolioWeights
        );

        CustodyVault vault = new CustodyVault();
        bytes32 salt = keccak256(abi.encodePacked(YieldType.Custody, name, symbol, underlying));
        address vaultProxy = address(new ERC1967Proxy{salt: salt}(address(vault), data));
        require(_vaults.contains(vaultProxy) == false, "CeDeFiManager: vault already exists");

        _vaults.add(vaultProxy);

        IVault(vaultProxy).setMinDepositAmount(minDepositAmount);
        IVault(vaultProxy).setMinWithdrawAmount(minWithdrawAmount);

        emit CreateVault(vaultProxy, uint256(YieldType.Custody), name, symbol, underlying);
    }

    // @dev create a new vault
    //    the yield type, name, symbol and underlying can only be added once
    function createVault(
        YieldType yieldType,
        string memory name,
        string memory symbol,
        address underlying,
        uint256 minDepositAmount,
        uint256 minWithdrawAmount,
        address[] memory portfolios,
        uint256[] memory portfolioWeights
    ) public onlyRole(ADMIN_ROLE) {
        // create new vault
        if (yieldType == YieldType.Custody) {
           createCustodyVault(name, symbol, underlying, portfolios, portfolioWeights, minDepositAmount, minWithdrawAmount);
        } else if (yieldType == YieldType.PrimeWallet) {
            // create prime wallet vault
        } else if (yieldType == YieldType.DefiProtocol) {
            // create defi protocol vault
        } else if (yieldType == YieldType.FromFund) {
            // create centralized fund vault
        } else {
            revert("CeDeFiManager: invalid yield type");
        }
    }

    // @dev get length of all active vaults
    function getVaultsLength() public view returns (uint256) {
        return _vaults.length();
    }

    // @dev get specific vault
    function getVault(uint256 index) public view returns (address) {
        return _vaults.at(index);
    }
}