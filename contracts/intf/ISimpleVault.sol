// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ISimpleVault is IERC20 {

    function deposit(address underlyingToken, uint256 amount) external payable;
    function requestWithdraw(uint256 amount) external returns(uint128 reqeustId);
    function withdraw(uint128 requestId) external;
    function getYieldType() external view returns (uint8);
    function getUnderlying() external view returns (address);
    function getCurrentUnitNav() external view returns (uint256);
    function getUsableShares(address account) external view returns(uint256);
    function minDepositAmount() external view returns (uint256);
    function minWithdrawAmount() external view returns (uint256);

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
    function setUnderlying(address _underlying) external;
    function pause() external;
    function unpause() external;
}
