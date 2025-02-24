// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IVault, YieldType} from "../intf/IVault.sol";
import {SimpleVaultBase} from "./SimpleVaultBase.sol";

import "hardhat/console.sol";

abstract contract SimpleVault is
    ERC20Upgradeable,
    PausableUpgradeable,
    SimpleVaultBase,
    IVault
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    event AddBlacklists(address[] users);
    event RemoveBlacklists(address[] users);
    event FreezeShares(address account, uint256 shares);
    event UnfreezeShares(address account, uint256 shares);

    event SetUnitNav(uint128 settlementPeriod, uint256 unitNav);
    event SetMinDepositAmount(uint256 amount);
    event SetMinWithdrawAmount(uint256 amount);
    event UpdatePortfolios(address[] portfolios, uint256[] weights);

    // @dev while users deposit underlying asset, how to allocate the asset to different portfolios,
    //  for different yield type vault, it should be implemented by different way
    function onDepositUnderlying(address from, uint256 underlyingAmount) internal virtual;
    // @dev while users withdraw underlying asset, how to withdraw the asset from different portfolios,
    //    implement by different way for different yield type vault
    function onWithdrawUnderlying(address from, uint256 underlyingAmount) internal virtual;

    function updatePortfolios(address[] calldata portfolios_, uint256[] calldata weights_) public onlyManager {
        uint256 totalWeight;
        uint256 len = portfolios_.length;
        for (uint256 i = 0; i < len; ) {
            bool success = _portfolios.add(portfolios_[i]);
            require(success, "Duplicated portfolio");

            portfolioWeights[portfolios_[i]] = weights_[i];
            totalWeight += weights_[i];

            unchecked { i++; }
        }
        require(totalWeight == Precision, "Invalid total weight");
        emit UpdatePortfolios(portfolios_, weights_);
    }

    // @dev to set the unit NAV of the current period
    function setUnitNav(uint256 unitNav) external onlyManager {
        uint128 index = settlementPeriod;
        periodUnitNav[index] = unitNav;
        unsettledWithdrawShares += periodWithdrawShares[index];

        ++settlementPeriod;

        emit SetUnitNav(index, unitNav);
    }

    // @dev set min deposit amount
    function setMinDepositAmount(uint256 amount) external onlyManager {
        require(amount > 0, "invalid amount");
        minDepositAmount = amount;

        emit SetMinDepositAmount(amount);
    }

    // @dev set min withdraw amount
    function setMinWithdrawAmount(uint256 amount) external onlyManager {
        require(amount > 0, "invalid amount");
        minWithdrawAmount = amount;

        emit SetMinWithdrawAmount(amount);
    }

    // @dev add blacklisted user
    function addBlacklist(address[] calldata users) external onlyManager {
        uint256 len = users.length;
        for (uint256 i = 0; i < len; ) {
            blacklisted[users[i]] = true;
            unchecked { i++; }
        }

        emit AddBlacklists(users);
    }

    // @dev remove blacklisted user
    function removeBlacklist(address[] calldata users) external onlyManager {
        uint256 len = users.length;
        for (uint256 i = 0; i < len; ) {
            delete blacklisted[users[i]];
            unchecked { i++; }
        }

        emit RemoveBlacklists(users);
    }

    // @dev freeze the shares of the target address
    function freezeShares(address account, uint256 shares) external onlyManager {
        uint256 leftShares = balanceOf(account);
        if (shares > leftShares) {
            shares = leftShares;
        }

        freezedShares[account] += shares;
        emit FreezeShares(account, shares);
    }

    // @dev unfreeze the shares of the target address
    function unfreezeShares(address account, uint256 shares) external onlyManager {
        uint256 freezed = freezedShares[account];
        if (shares > freezed) {
            shares = freezed;
        }

        freezedShares[account] -= shares;
        emit UnfreezeShares(account, shares);
    }

    // @dev to pause the vault
    function pause() external onlyManager {
        _pause();
    }

    // @dev to unpause the vault
    function unpause() external onlyManager {
        _unpause();
    }

    // @dev total supply of shares, it should substract the withdrew shares of unsettled withdraw requests
    function totalSupply()
        public
        view
        override(IERC20, ERC20Upgradeable)
        returns (uint256)
    {
        uint256 rawSupply = super.totalSupply();
        return rawSupply - unsettledWithdrawShares;
    }

    // @dev transfer shares token to the target address, should check the freezed shares
    function transfer(address recipient, uint256 amount)
        public
        override(IERC20, ERC20Upgradeable)
        whenNotPaused
        notBlacklisted
        returns (bool)
    {
        require(getUsableShares(msg.sender) >= amount, "Insufficient balance");
        return super.transfer(recipient, amount);
    }

    // @dev get usable shares of the target address
    function getUsableShares(address account) public view returns(uint256) {
        uint256 rawBalance = balanceOf(account);
        uint256 freezed = freezedShares[account];
        uint256 ongoingWithdrawShares = getOngoingWithdrawShares(account);

        return rawBalance > (freezed + ongoingWithdrawShares) ?
               rawBalance - freezed - ongoingWithdrawShares :
               0;
    }

    // @dev to calculate all the ongoing withdraw amount
    function getOngoingWithdrawShares(address account) public view returns(uint256) {
        uint256 len = _withdrawRequestIds[account].length();
        uint256 shares;
        for (uint256 i = 0; i < len; ) {
            uint128 requestId = uint128(_withdrawRequestIds[account].at(i));
            shares += withdrewRequests[account][requestId].requestShares;
            unchecked { i++; }
        }

        return shares;
    }

    // @dev deposit underlying asset to the vault, mint shares to the target address
    function deposit(uint256 underlyingAmount)
        external
        whenNotPaused
        notBlacklisted
        lock
    {
        require(underlyingAmount >= minDepositAmount, "deposit amount too small");

        onDepositUnderlying(msg.sender, underlyingAmount);
        uint256 sharesAmount = mintShares(msg.sender, underlyingAmount);

        // emit enough information for accounting
        address[] memory p = portfolios();
        uint256[] memory w = weights();
        emit Deposited(
            msg.sender,
            underlyingAmount,
            sharesAmount,
            periodUnitNav[settlementPeriod],
            settlementPeriod,
            p,
            w,
            block.timestamp
        );
    }

    // @dev request to withdraw shares, it will be executed while current period is settled
    function requestWithdraw(uint256 shareAmount)
        external
        whenNotPaused
        notBlacklisted
        lock
        returns (uint128)
    {
        uint256 sharesBalance = getUsableShares(msg.sender);
        if (shareAmount != sharesBalance) { // make sure sender can withdraw all shares
            require(shareAmount >= minWithdrawAmount, "withdraw amount too small");
        }
        require(sharesBalance >= shareAmount, "Insufficient balance");

        // to record the request information, merge multiple requests into one request
        uint128 requestId = settlementPeriod;
        _withdrawRequestIds[msg.sender].add(requestId);

        WithdrewRequest storage request = withdrewRequests[msg.sender][requestId];
        request.requestShares += shareAmount;
        request.targetPeriod = requestId;
        request.requestTimestamp = uint64(block.timestamp);
        // to record the total withdraw shares of this period, and sub it while this period is settled
        // so these shares stop yield
        periodWithdrawShares[requestId] += shareAmount;

        emit WithdrawRequested(
            requestId,
            msg.sender,
            shareAmount,
            block.timestamp
        );

        return requestId;
    }

    // @dev withdraw underlying asset from the vault, burn shares from the target address
    //    only executalbe while the period is settled
    //    the requestId must be call `requestWithdraw` to get
    function withdraw(uint128 requestId)
        external
        whenNotPaused
        notBlacklisted
        lock
    {
        require(requestId < settlementPeriod, "not settled yet");

        require(_withdrawRequestIds[msg.sender].contains(requestId), "not requested");
        _withdrawRequestIds[msg.sender].remove(requestId);

        WithdrewRequest storage request = withdrewRequests[msg.sender][requestId];
        require(request.requestShares > 0, "no request found");

        require(request.executedTimestamp == 0, "already executed");
        request.executedTimestamp = uint64(block.timestamp);

        unsettledWithdrawShares -= request.requestShares;

        uint256 underlyingAmount = burnShares(msg.sender, requestId, request.requestShares);
        onWithdrawUnderlying(msg.sender, underlyingAmount);

        emit WithdrawFinished(
            requestId,
            msg.sender,
            request.requestShares,
            periodUnitNav[requestId],
            block.timestamp
        );
    }

    // @dev mint shares to the target address, it should be calculated as : shares = amount / unitNav
    // @param to the target address
    // @param underlyingAmount the amount of underlying asset
    function mintShares(address to, uint256 underlyingAmount) internal returns(uint256) {
        uint256 shares;
        if (settlementPeriod == 1) {
            shares = underlyingAmount;
        } else {
            uint256 unitNav = periodUnitNav[settlementPeriod];
            require(unitNav > 0, "oops: unit nav");
            shares = (underlyingAmount * Precision) / unitNav;
        }
        _mint(to, shares);

        return shares;
    }

    // @dev burn shares from the target address, it should be calculated as : amount = shares * unitNav
    // @param from the target address
    // @param shares the amount of shares
    function burnShares(address from, uint128 requestId, uint256 sharesAmount) internal returns(uint256) {
        uint256 unitNav = periodUnitNav[requestId];
        uint256 amount = (sharesAmount * unitNav) / Precision;
        // burn shares and return the amount of underlying asset
        _burn(from, sharesAmount);
        return amount;
    }

    function getYieldType() public view override returns (YieldType) {
        return yieldType;
    }

     function portfolios() public view returns (address[] memory) {
        return EnumerableSet.values(_portfolios);
    }

    function weights() public view returns (uint256[] memory) {
        uint256 len = _portfolios.length();
        uint256[] memory result = new uint256[](len);
        for (uint256 i = 0; i < len; ) {
            result[i] = portfolioWeights[_portfolios.at(i)];
            unchecked { i++; }
        }
        return result;
    }
}