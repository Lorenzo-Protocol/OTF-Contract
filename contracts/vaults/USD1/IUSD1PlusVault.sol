// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IUSD1PlusVault {
    function mint(address to, uint256 sharesAmount) external;
}