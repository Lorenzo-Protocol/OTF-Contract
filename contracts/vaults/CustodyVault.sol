// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SimpleVault} from "./SimpleVault.sol";
import {YieldType} from "../intf/IVault.sol";

import "hardhat/console.sol";

contract CustodyVault is
    UUPSUpgradeable,
    SimpleVault
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
        uint256[] calldata weights_
    ) public initializer {
        require(underlying_ != address(0), "Invalid underlying");
        require(portfolios_.length == weights_.length, "Invalid portfolios or weights");

        __UUPSUpgradeable_init();
        __ERC20_init(name_, symbol_);

        cedefiManager = msg.sender;
        underlying = underlying_;
        settlementPeriod = 1;

        updatePortfolios(portfolios_, weights_);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyManager {}

    // to handle the depoisted underlying asset
    function onDepositUnderlying(address from, uint256 underlyingAmount)
        internal
        override
    {
        IERC20 underlyingToken = IERC20(underlying);

        SafeERC20.safeTransferFrom(underlyingToken, from, address(this), underlyingAmount);

        address[] memory portfolios = _portfolios.values();
        uint256 len = portfolios.length;
        for (uint256 i = 0; i < len;) {
            address portfolio = portfolios[i];
            uint256 weight = portfolioWeights[portfolio];
            uint256 splitUnderlying = (underlyingAmount * weight) / Precision;

            SafeERC20.safeTransfer(underlyingToken, portfolio, splitUnderlying);

            unchecked { i++; }
        }
    }
    // to handle the withdrawed underlying asset
    function onWithdrawUnderlying(address to, uint256 underlyingAmount)
        internal
        override
    {
        IERC20 underlyingToken = IERC20(underlying);
        SafeERC20.safeTransfer(underlyingToken, to, underlyingAmount);
    }
}