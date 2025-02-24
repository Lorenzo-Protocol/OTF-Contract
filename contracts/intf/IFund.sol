// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IFund {

    event Deposited(
        address indexed sender,
        uint256 underlyingAmount,
        uint256 sharesAmount,
        uint256 unitNav,
        uint128 settlementPeriod,
        address[] subVaults,
        uint256[] percentages,
        uint256 timestamp
    );

    event WithdrawRequested(
        uint256 indexed requestId,
        address indexed sender,
        uint256 sharesAmount,
        uint256 settlementPeriod,
        address[] subVaults,
        uint256[] percentages,
        uint256 timestamp
    );

    event WithdrawFinished(
        uint256 indexed requestId,
        address indexed sender,
        uint256 sharesAmount,
        uint256 unitNav,
        uint256 settlementPeriod,
        address[] subVaults,
        uint256[] percentages,
        uint256 timestamp
    );

    function deposit(uint256 amount) external;
    function requestWithdraw(uint256 amount) external returns(uint256 reqeustId);
    function withdraw(uint256 requestId) external;
}