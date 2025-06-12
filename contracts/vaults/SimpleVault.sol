// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Vault} from "./Vault.sol";
import {YieldType} from "../intf/IVault.sol";

contract SimpleVault is
    UUPSUpgradeable,
    Vault
{
    using EnumerableSet for EnumerableSet.AddressSet;

    constructor() {
        _disableInitializers();
        yieldType = YieldType.Custody;
    }

    function initialize(
        string calldata name_,
        string calldata symbol_,
        address underlying_,
        address[] calldata portfolios_,
        uint256[] calldata weights_,
        address cedefiManager_
    ) public initializer {
        require(underlying_ != address(0), "Invalid underlying");
        require(portfolios_.length == weights_.length, "Invalid portfolios or weights");

        __UUPSUpgradeable_init();
        __ERC20_init(name_, symbol_);

        cedefiManager = cedefiManager_;
        underlying = underlying_;
        settlementPeriod = 1;

        updatePortfolios(portfolios_, weights_);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyManager {}

    receive() external payable {}

    // to handle the depoisted underlying asset
    function onDepositUnderlying(address from, uint256 underlyingAmount)
        internal
        override
        returns (uint256 sharesAmount, uint256 unitNav)
    {
        if (underlying == NATIVE_TOKEN) {
            require(msg.value == underlyingAmount, "send value != deposit amount");
        } else {
            IERC20 underlyingToken = IERC20(underlying);
            SafeERC20.safeTransferFrom(underlyingToken, from, address(this), underlyingAmount);
        }

        address[] memory portfolios = _portfolios.values();
        uint256 len = portfolios.length;
        uint256 totalTransferred;
        for (uint256 i; i < len;) {
            address portfolio = portfolios[i];
            uint256 weight = portfolioWeights[portfolio];
            uint256 splitUnderlying = (underlyingAmount * weight) / Precision;

            sendUnderlying(portfolio, splitUnderlying);
            totalTransferred += splitUnderlying;
            unchecked { i++; }
        }

        if (totalTransferred < underlyingAmount) {
            sendUnderlying(portfolios[0], underlyingAmount - totalTransferred);
        }
        // mint all the shares to depositor
        (sharesAmount, unitNav) = mintShares(from, underlyingAmount);
    }
    // to handle the withdrawed underlying asset
    function onWithdrawUnderlying(address to, uint256 underlyingAmount)
        internal
        override
    {
        sendUnderlying(to, underlyingAmount);
    }
}