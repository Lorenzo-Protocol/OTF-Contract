// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {IVault, YieldType} from "./intf/IVault.sol";
import {CeDeFiManagerBase} from "./CeDeFiManagerBase.sol";

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

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(BOSS_ROLE){
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

    // @dev add or removeallowed vaults functions, which CeDeFiManager can call.
    function setInvokableVaultsFuncs(
        bytes4[] memory funcSelectors,
        bool[] memory isAllowed
    )
        public
        onlyRole(ADMIN_ROLE)
    {
        require(funcSelectors.length == isAllowed.length, "CeDeFiManager: mismatched length");

        uint256 len = funcSelectors.length;
        for (uint256 i; i < len; ) {
            allowedVaultsFuncs[funcSelectors[i]] = isAllowed[i];
            unchecked { ++i; }
        }
    }

    // @dev manage the vaults
    function executeCommand(address vault, bytes memory data) public onlyRole(OPERATOR_ROLE) {
        require(_vaults.contains(vault), "CeDeFiManager: vault not exist");
        bytes4 selector;
        assembly {
            selector := mload(add(data, 32))
        }
        require(allowedVaultsFuncs[selector], "CeDeFiManager: vault function not allowed");

        (bool success, bytes memory returndata) = vault.call(data);
        require(success, string(returndata));
    }

    // @dev to create a custody vault
    function createSimpleVault(
        CreateVaultParams memory params,
        address implementation
    )
        internal
    {
        require(params.portfolios.length == params.portfolioWeights.length, "CeDeFiManager: invalid length portfolios and weights");
        uint len = params.portfolios.length;
        for (uint i = 0; i < len; ) {
            require(_activePortfolios.contains(params.portfolios[i]), "CeDeFiManager: portfolio not exists");
            unchecked { ++i; }
        }

        bytes memory data = abi.encodeWithSignature(
            "initialize(string,string,address)",
            params.name, params.symbol,address(this)
        );

        bytes32 salt = keccak256(abi.encode(params.name, params.symbol));
        address vaultProxy = address(new ERC1967Proxy{salt: salt}(implementation, data));
        require(_vaults.contains(vaultProxy) == false, "CeDeFiManager: vault already exists");
        require(IVault(vaultProxy).getYieldType() == params.yieldType, "CeDeFiManager: vault yield type mismatch");

        _vaults.add(vaultProxy);

        IVault(vaultProxy).setUnderlying(params.underlying);
        IVault(vaultProxy).updatePortfolios(params.portfolios, params.portfolioWeights);
        IVault(vaultProxy).setMinDepositAmount(params.minDepositAmount);
        IVault(vaultProxy).setMinWithdrawAmount(params.minWithdrawAmount);

        emit CreateVault(vaultProxy, params.yieldType, params.name, params.symbol, params.underlying);
    }

    // @dev create a new vault
    //    the yield type, name, symbol and underlying can only be added once
    struct CreateVaultParams {
        YieldType yieldType;
        string name;
        string symbol;
        address underlying;
        uint256 minDepositAmount;
        uint256 minWithdrawAmount;
        address[] portfolios;
        uint256[] portfolioWeights;
    }
    function createVault(
        CreateVaultParams memory params,
        address implementation
    ) public onlyRole(ADMIN_ROLE) {
        // create new vault
        if (params.yieldType == YieldType.Custody) {
           createSimpleVault(params, implementation);
        } else if (params.yieldType == YieldType.PrimeWallet) {
            // create prime wallet vault
        } else if (params.yieldType == YieldType.DefiProtocol) {
            // create defi protocol vault
        } else if (params.yieldType == YieldType.FromFund) {
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