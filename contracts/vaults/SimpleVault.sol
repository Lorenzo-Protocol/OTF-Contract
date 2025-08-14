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
        address cedefiManager_
    ) public initializer {

        __UUPSUpgradeable_init();
        __ERC20_init(name_, symbol_);

        cedefiManager = cedefiManager_;
        settlementPeriod = 1;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyManager {}

    receive() external payable {}

    function setUnderlying(address _underlying) public onlyManager {
        require(_underlying != address(0), "invalid underlying");
        underlying = _underlying;
    }
    // to handle the depoisted underlying asset
    function onDepositUnderlying(address from, address underlyingToken, uint256 underlyingAmount)
        internal
        override
        returns (uint256 sharesAmount, uint256 unitNav)
    {
        uint256 alignedAmount = alignDepositAmount(underlyingAmount, underlyingToken);
        require(alignedAmount >= minDepositAmount, "deposit amount too small");

        address[] memory portfolios = _portfolios.values();
        uint256 len = portfolios.length;
        uint256 totalTransferred;

        if (underlyingToken == NATIVE_TOKEN) {
            require(msg.value == underlyingAmount, "send value != deposit amount");

            for (uint256 i; i < len;) {
                address portfolio = portfolios[i];
                uint256 weight = portfolioWeights[portfolio];
                uint256 splitUnderlying = (alignedAmount * weight) / Precision;

                (bool success, bytes memory data) = portfolio.call{value: splitUnderlying}("");
                require(success, string(data));

                totalTransferred += splitUnderlying;
                unchecked { i++; }
            }

            if (totalTransferred < alignedAmount) {
                (bool success, bytes memory data) = portfolios[0].call{value: alignedAmount - totalTransferred}("");
                require(success, string(data));
            }
        } else {
            IERC20 assetToken = IERC20(underlyingToken);
            SafeERC20.safeTransferFrom(assetToken, from, address(this), underlyingAmount);

            for (uint256 i; i < len;) {
                address portfolio = portfolios[i];
                uint256 weight = portfolioWeights[portfolio];
                uint256 splitUnderlying = (alignedAmount * weight) / Precision;

                SafeERC20.safeTransfer(assetToken, portfolio, splitUnderlying);
                totalTransferred += splitUnderlying;
                unchecked { i++; }
            }

            if (totalTransferred < alignedAmount) {
                SafeERC20.safeTransfer(assetToken, portfolios[0], alignedAmount - totalTransferred);
            }
        }

        // mint all the shares to depositor
        (sharesAmount, unitNav) = mintShares(from, alignedAmount);
    }
    // to handle the withdrawed underlying asset
    function onWithdrawUnderlying(address to, uint256 underlyingAmount)
        internal
        override
    {
        sendUnderlying(to, underlyingAmount);
    }
}