// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IUSD1Vault {
    function settlementPeriod() external view returns (uint128);
    function getUnitNav(uint128 peroid) external view returns (uint256);
    function swapToSusd1(address to, uint256 shareAmount) external;
    function swapToUsd1Plus(address to, uint256 shareAmount) external;
}