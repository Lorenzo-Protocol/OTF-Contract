// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

enum YieldType {
    None,
    Custody,      // underlying assert is custodyed to third party, like Ceffu
    PrimeWallet,  // underlying assert is deposited to prime wallet, like coinbase prime wallet
    DefiProtocol, // underlying assert is deposited to defi protocol
    FromFund      // underlying assert is deposited to centralized fund
}

interface IVault is IERC20 {
    event Deposited(
        address indexed sender,
        uint256 amount,
        uint256 shares,
        uint256 unitNav,
        uint128 settlementPeriod,
        address[] portfolios,
        uint256[] weights,
        uint256 timestamp
    );

    event WithdrawRequested(
        uint128 indexed requestId,
        address indexed sender,
        uint256 sharesAmount,
        uint256 timestamp
    );

    event WithdrawFinished(
        uint128 indexed requestId,
        address indexed sender,
        uint256 sharesAmount,
        uint256 unitNav,
        uint256 timestamp
    );

    event UpdatePortfolio(address[] portfolios, uint256[] weights);

    function deposit(uint256 amount) external payable;
    function requestWithdraw(uint256 amount) external returns(uint128 reqeustId);
    function withdraw(uint128 requestId) external;
    function getYieldType() external view returns (YieldType);

    // manager functions
    function updatePortfolios(address[] calldata portfolios, uint256[] calldata weights) external;
    function setMinDepositAmount(uint256 amount) external;
    function setMinWithdrawAmount(uint256 amount) external;
    function setUnitNav(uint256 unitNav) external;
    function addBlacklist(address[] calldata users) external;
    function removeBlacklist(address[] calldata users) external;
    function freezeShares(address account, uint256 shares) external;
    function unfreezeShares(address account, uint256 shares) external;
    function setTransferable(bool transferable_) external;
    function pause() external;
    function unpause() external;
}
