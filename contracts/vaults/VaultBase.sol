// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {YieldType} from "../intf/IVault.sol";

contract VaultBase {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    uint256 public constant Precision = 10 ** 18; // the precision is the same as decimals

    modifier onlyManager() {
        require(msg.sender == cedefiManager, "Only cedefi manager");
        _;
    }

    modifier lock() {
        require(!_locked, "Locked");
        _locked = true;
        _;
        _locked = false;
    }

    modifier notBlacklisted() {
        require(!blacklisted[msg.sender], "Blacklisted");
        _;
    }

    struct WithdrewRequest {
        uint256 requestShares; // requested shares
        uint128 targetPeriod;  // in which period this withdraw request can be executed;
        uint64  requestTimestamp;      // timestamp of this request, if request many times, only the latest one is recorded
        uint64  executedTimestamp;     // timestamp of this request is executed
    }

    YieldType internal immutable yieldType; // yield type

    /** basic information */
    address public cedefiManager; // admin address, this is creater address of CeDeFi Layer.
    address public underlying; // underlying asset

    /**   Manage information */
    bool private _locked; // locked entrance
    bool public transferable; // the shares are transferable or not
    mapping(address => bool) public blacklisted; // blacklisted users
    mapping(address => uint256) public freezedShares;   // freezed shares
    uint256 public minDepositAmount; // minimum deposit amount
    uint256 public minWithdrawAmount; // maximum withdraw amount

    EnumerableSet.AddressSet internal _portfolios;          // current portfolios
    mapping(address => uint256) public portfolioWeights;    // portfolio -> weight

    uint128 public settlementPeriod; // current settlement period
    mapping(uint128 settlementPeriod => uint256) public periodUnitNav; // settlement period -> unit NAV of each period
    mapping(uint128 settlementPeriod => uint256) public periodWithdrawShares; // settlement period -> total shares  of each period
    uint256 public unsettledWithdrawShares; // total unsettled withdraw shares, someone may request withdraw, but not executed yet

    mapping(address => EnumerableSet.UintSet) internal _withdrawRequestIds; // withdraw request ids
    mapping(address user => mapping(uint128 settlementPeriod => WithdrewRequest)) public withdrewRequests; // user -> settlementPeriod -> withdrew request

    mapping(address => bool) public acceptUnderlying; // accept underlying assets, such as underlying is USD1, and also support USDT, USDC, etc.
    // @dev padding for future upgrade
    uint256[256] private _gap;
}