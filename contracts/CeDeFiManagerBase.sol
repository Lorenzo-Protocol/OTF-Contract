// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract CeDeFiManagerBase {
    // boss roles can add or remove roles
    bytes32 public constant BOSS_ROLE = keccak256("BOSS_ROLE");
    // admin role can upgrade this contracts and manage vaults
    bytes32 public constant ADMIN_ROLE = keccak256("MANAGER_ROLE");
    // create vault role can create new vaults
    bytes32 public constant OPERATOR_ROLE = keccak256("CREATE_VAULT_ROLE");

    event AddPortfolios(address[] portfolios);
    event DeletePortfolios(address[] portfolios);
    event CreateVault(address indexed vault, uint256 yieldType, string name, string symbol, address underlying);

    EnumerableSet.AddressSet internal _activePortfolios;
    EnumerableSet.AddressSet internal _vaults;
}