// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IVault, YieldType} from "../intf/IVault.sol";
import {VaultBase} from "./VaultBase.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract Vault is
    ERC20Upgradeable,
    PausableUpgradeable,
    VaultBase,
    IVault
{
    address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

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
    event SetTransferable(bool transferable);
    event SetAcceptUnderlying(address[] underlyingTokens, bool[] accepts);
    event ResetUnitNav(uint128 period, uint256 unitNav);

    // @dev while users deposit underlying asset, how to allocate the asset to different portfolios,
    //  for different yield type vault, it should be implemented by different way
    function onDepositUnderlying(address from, address underlyingToken, uint256 underlyingAmount) internal virtual returns (uint256 sharesAmount, uint256 unitNav);
    // @dev while users withdraw underlying asset, how to withdraw the asset from different portfolios,
    //    implement by different way for different yield type vault
    function onWithdrawUnderlying(address from, uint256 underlyingAmount) internal virtual;

    function updatePortfolios(address[] memory  portfolios_, uint256[] memory weights_) public onlyManager {
        require(portfolios_.length == weights_.length, "mismatch length of portfolios and weights");

        // remove old portfolios
        address[] memory oldPortfolios = EnumerableSet.values(_portfolios);
        for (uint256 i = 0; i < oldPortfolios.length; i++) {
            delete portfolioWeights[oldPortfolios[i]];
            _portfolios.remove(oldPortfolios[i]);
        }

        // add new portfolios
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
    // while the unit nav settled, all these withdraw reqeusts are settled,
    // then no matter they finish or not finish the withdraw,
    // all the requested shares stop yielding,
    // and the totalSupply() MUST substract these shares.
    //
    // CAUTION: for the same period, this method can only be called once
    function setUnitNav(uint256 unitNav) external onlyManager {
        uint128 index = settlementPeriod;
        require(periodUnitNav[index] == 0, "period settled already");
        // FIXME: should do this check??????
        require(unitNav != 0, "invalid unit nav");

        periodUnitNav[index] = unitNav;
        unsettledWithdrawShares += periodWithdrawShares[index];

        ++settlementPeriod;

        emit SetUnitNav(index, unitNav);
    }

    // @dev reset the unit nav of the target period
    // it only reset the unit nav of the target period, but not change the settlementPeriod
    // ONLY for mis setting the unit nav of the target period
    function resetUnitNav(uint128 period, uint256 unitNav) external onlyManager {
        require(period < settlementPeriod, "period not settled");
        require(unitNav > 0, "invalid unit nav");

        periodUnitNav[period] = unitNav;

        emit ResetUnitNav(period, unitNav);
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
        uint256 leftShares = getUsableShares(account);
        if (shares > leftShares) {
            shares = leftShares;
        }

        frozenShares[account] += shares;
        emit FreezeShares(account, shares);
    }

    // @dev unfreeze the shares of the target address
    function unfreezeShares(address account, uint256 shares) external onlyManager {
        uint256 freezed = frozenShares[account];
        if (shares > freezed) {
            shares = freezed;
        }

        frozenShares[account] -= shares;
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

    // @dev set the accept underlying token
    // these tokens can deposit to the vault, but while withdraw, only the underlying token provide
    function setAcceptUnderlying(address[] calldata underlyingTokens, bool[] calldata accepts) external onlyManager {
        uint256 len = underlyingTokens.length;
        require(len == accepts.length, "length mismatch");
        for (uint256 i; i < len; ) {
            acceptUnderlying[underlyingTokens[i]] = accepts[i];
            unchecked { i++; }
        }

        emit SetAcceptUnderlying(underlyingTokens, accepts);
    }

    // @dev transfer from/to underlying token
    function sendUnderlying(address to, uint256 underlyingAmount) internal {
        if (underlying == NATIVE_TOKEN) {
            (bool success, bytes memory data) = to.call{value: underlyingAmount}("");
            require(success, string(data));
        } else {
            IERC20 underlyingToken = IERC20(underlying);
            SafeERC20.safeTransfer(underlyingToken, to, underlyingAmount);
        }
    }

    // @dev set the shares transferable or not
    function setTransferable(bool transferable_) external onlyManager {
        require(transferable != transferable_, "same transferable");
        transferable = transferable_;
        emit SetTransferable(transferable_);
    }

    // @dev total supply of shares, it should substract the withdrew shares of unsettled withdraw requests
    function totalSupply()
        public
        virtual
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
        virtual
        override(IERC20, ERC20Upgradeable)
        whenNotPaused
        notBlacklisted
        returns (bool)
    {
        require(transferable, "Not transferable");
        require(getUsableShares(msg.sender) >= amount, "Insufficient balance");
        return super.transfer(recipient, amount);
    }

    // @dev ban transferFrom
    //  not allowed approve someone else to transfer shares
    function transferFrom(address from, address to, uint256 value)
        public
        virtual
        override(IERC20, ERC20Upgradeable)
        whenNotPaused
        notBlacklisted
        returns (bool)
    {
        require(transferable, "Not transferable");
        require(!blacklisted[from], "from is blacklisted");
        require(getUsableShares(from) >= value, "Insufficient balance");
        return super.transferFrom(from, to, value);
    }

    // @dev get usable shares of the target address
    function getUsableShares(address account) public view returns(uint256) {
        uint256 rawBalance = balanceOf(account);
        uint256 freezed = frozenShares[account];
        uint256 ongoingWithdrawShares = getOngoingWithdrawShares(account);
        // it must be but just check it
        return rawBalance > (freezed + ongoingWithdrawShares) ?
               rawBalance - freezed - ongoingWithdrawShares :
               0;
    }

    // @dev to calculate all the ongoing withdraw amount,
    // include those settled but not finished withdraw requests
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

    // @dev align the deposit amount decimals to the underlying token decimals
    function alignDepositAmount(uint256 rawAmount, address underlyingToken)
        internal
        view
        returns(uint256)
    {
        if (underlyingToken == underlying) {
            return rawAmount;
        }

        uint256 decimals = underlyingToken == NATIVE_TOKEN ? 18 : IERC20Metadata(underlyingToken).decimals();
        uint256 targetDecimals = underlying == NATIVE_TOKEN ? 18 : IERC20Metadata(underlying).decimals();

        if (decimals > targetDecimals) {
            return rawAmount / 10 ** (decimals - targetDecimals);
        } else if (decimals == targetDecimals) {
            return rawAmount;
        } else {
            return rawAmount * 10 ** (targetDecimals - decimals);
        }
    }

    // @dev deposit underlying asset to the vault, mint shares to the target address
    function deposit(address underlyingToken, uint256 underlyingAmount)
        external
        whenNotPaused
        notBlacklisted
        lock
        payable
    {
        require(acceptUnderlying[underlyingToken] || underlyingToken == underlying || underlyingToken == NATIVE_TOKEN, "not accept underlying");

        (uint256 sharesAmount, uint256 unitNav) = onDepositUnderlying(msg.sender, underlyingToken, underlyingAmount);

        // emit enough information for accounting
        address[] memory p = portfolios();
        uint256[] memory w = weights();
        emit Deposited(
            msg.sender,
            underlyingToken,
            underlyingAmount,
            sharesAmount,
            unitNav,
            settlementPeriod,
            p,
            w,
            block.timestamp
        );
    }

    function _doRequestWithdraw(uint256 shareAmount) internal returns (uint128) {
        require(shareAmount > 0, "share amount is zero");
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
        // so these shares stop yielding
        periodWithdrawShares[requestId] += shareAmount;

        return requestId;
    }

    // @dev request to withdraw shares, it will be executed while current period is settled
    function requestWithdraw(uint256 shareAmount)
        public
        virtual
        whenNotPaused
        notBlacklisted
        lock
        returns (uint128)
    {
        uint128 requestId = _doRequestWithdraw(shareAmount);

        emit WithdrawRequested(
            requestId,
            msg.sender,
            shareAmount,
            block.timestamp
        );

        return requestId;
    }

    // @dev withdraw underlying asset from the vault, burn shares from the target address
    //    only executalbe more than two periods are settled
    //    the requestId is the return value of method `requestWithdraw`
    function withdraw(uint128 requestId)
        public
        virtual
        whenNotPaused
        notBlacklisted
        lock
    {
        uint128 settledPeriod = requestId + 1;
        require(settledPeriod < settlementPeriod, "should wait more than two periods");

        require(_withdrawRequestIds[msg.sender].contains(requestId), "not requested");
        _withdrawRequestIds[msg.sender].remove(requestId);

        WithdrewRequest storage request = withdrewRequests[msg.sender][requestId];
        require(request.requestShares > 0, "no request found");

        require(request.executedTimestamp == 0, "already executed");
        request.executedTimestamp = uint64(block.timestamp);

        unsettledWithdrawShares -= request.requestShares;

        (uint256 underlyingAmount, uint256 unitNav)
            = burnShares(msg.sender, settledPeriod, request.requestShares);
        onWithdrawUnderlying(msg.sender, underlyingAmount);

        emit WithdrawFinished(
            requestId,
            msg.sender,
            request.requestShares,
            unitNav,
            block.timestamp
        );
    }

    // @dev mint shares to the target address, it should be calculated as : shares = amount / unitNav
    // @param to the target address
    // @param underlyingAmount the amount of underlying asset
    function mintShares(address to, uint256 underlyingAmount) internal returns(uint256 sharesAmount, uint256 unitNav) {
        unitNav = getUnitNav(settlementPeriod);
        require(unitNav > 0, "oops: zero unit nav");
        sharesAmount = (underlyingAmount * Precision) / unitNav;

        _mint(to, sharesAmount);
    }

    // @dev burn shares from the target address, it should be calculated as : amount = shares * unitNav
    // @param from the target address
    // @param shares the amount of shares
    function burnShares(address from, uint128 settledPeriod, uint256 sharesAmount) internal returns(uint256, uint256) {
        uint256 unitNav = getUnitNav(settledPeriod);
        require(unitNav > 0, "oops: zero unit nav");
        uint256 amount = (sharesAmount * unitNav) / Precision;
        // burn shares and return the amount of underlying asset
        _burn(from, sharesAmount);
        return (amount, unitNav);
    }
    // @dev get the yield type of the vault
    function getYieldType() public view override returns (YieldType) {
        return yieldType;
    }
    // @dev get portfolios list
    function portfolios() public view returns (address[] memory) {
        return EnumerableSet.values(_portfolios);
    }
    // @dev get weights of the portfolios
    function weights() public view returns (uint256[] memory) {
        uint256 len = _portfolios.length();
        uint256[] memory result = new uint256[](len);
        for (uint256 i = 0; i < len; ) {
            result[i] = portfolioWeights[_portfolios.at(i)];
            unchecked { i++; }
        }
        return result;
    }
    // @dev get current unit nav
    // @param period the period to get the unit nav, period should gte 1
    function getUnitNav(uint128 period) public view returns (uint256) {
        if (period == 0) {
            return 0;
        } else if (period == 1) {
            if (underlying == NATIVE_TOKEN) {
                return 10 ** 18;
            } else {
                IERC20Metadata underlyingToken = IERC20Metadata(underlying);
                return 10 ** underlyingToken.decimals();
            }
        } else {
            return periodUnitNav[period - 1];
        }
    }
}