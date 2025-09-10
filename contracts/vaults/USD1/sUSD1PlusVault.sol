// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {Vault} from "../Vault.sol";
import {YieldType} from "../../intf/IVault.sol";
import {IUSD1PlusVault} from "./IUSD1PlusVault.sol";

contract sUSD1PlusVault is
    UUPSUpgradeable,
    EIP712Upgradeable,
    Vault
{
    using EnumerableSet for EnumerableSet.AddressSet;
    // users deposit usd1 to the vault, and get a pending shares waiting for KYT
    event PendingShares(address indexed user, uint128 indexed period, uint256 shares);
    // users confirm the shares after KYT passed
    event ConfirmShares (address indexed user, bytes32 indexed txHash, uint128 indexed period, uint256 shares);
    // users refund the shares after KYT failed
    event RefundShares  (address indexed user, bytes32 indexed txHash, uint128 indexed period, uint256 shares);
    // role setted
    event RoleSetted(bytes32 indexed role, address indexed account, address indexed sender, bool isGrant);
    // minter mint
    event MinterMint(address indexed to, uint256 sharesAmount, address sender);
    // burner burn
    event BurnerBurn(address indexed from, uint256 sharesAmount, address sender);
    // pendle deposit
    event DirectDeposit(address indexed user, uint128 period, address underlyingToken, uint256 underlyingAmount, uint256 sharesAmount);

    bytes32 public constant CONFIRM_SHARE = keccak256("ConfirmShare(uint128 period,bytes32 txHash,address user,uint256 sharesAmount)");
    bytes32 public constant REFUND_SHARE = keccak256("RefundShare(uint128 period,bytes32 txHash,address user,uint256 sharesAmount)");

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");  // 0x01
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");  // 0x02
    bytes32 public constant DEPOSIT_ROLE = keccak256("DEPOSIT_ROLE"); // 0x04

    mapping(address => mapping(uint128 => uint256)) public pendingShares; // user -> period -> pending shares
    mapping(address => bool) public signers; // signer -> is signer
    mapping(bytes32 => bool) public confirmedTx; // txHash -> is confirmed
    mapping(bytes32 => bool) public refundedTx; // txHash -> is refunded

    // address of the USD1+ vault
    IUSD1PlusVault public usd1PlusVault;

    // record the confirmed shares of the user of a period,
    // because the user can not request withdraw the confirmed shares in the same period,
    // the confirmed shares must stay in the vault for at least next period
    mapping(address => mapping(uint128 => uint256)) public confirmedShares; // user -> period -> confirmed shares

    // add roles for minter and burner for chainlink ccip @Sep. 3, 2025
    // mint role:  0x01, burner role: 0x02, depositor role: 0x04
    mapping(address => uint256) public roles; // account -> role
    // ----------- ADD STATE VARIABLES -----------
    // -------------------------------------------

    modifier onlyMinter() {
        require(roles[msg.sender] & uint256(0x01) == uint256(0x01), "minter only");
        _;
    }
    modifier onlyBurner() {
        require(roles[msg.sender] & uint256(0x02) == uint256(0x02), "burner only");
        _;
    }
    modifier onlyDepositor() {
        require(roles[msg.sender] & uint256(0x04) == uint256(0x04), "depositor only");
        _;
    }

    constructor() {
        _disableInitializers();
        yieldType = YieldType.Custody;
    }

    // @dev initialize the usd1 vault
    // @param name_ the name of the vault
    // @param symbol_ the symbol of the vault
    // @param underlying_ the underlying asset of the vault
    // @param portfolios_ the portfolios of the vault
    // @param weights_ the weights of the portfolios
    // @param cedefiManager_ the cedefi manager of the vault
    function initialize(
        string calldata name_,
        string calldata symbol_,
        address cedefiManager_
    ) public initializer {
        require(cedefiManager_ != address(0), "Invalid cedefi manager");

        __EIP712_init("USD1Vault", "1.0");
        __UUPSUpgradeable_init();
        __ERC20_init(name_, symbol_);

        cedefiManager = cedefiManager_;

        settlementPeriod = 1;
        transferable = true;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyManager {}

    receive() external payable {
        revert("Not allowed to receive native token");
    }

    // @dev set underlying token
    function setUnderlying(address _underlying) public onlyManager {
        require(_underlying != address(0), "invalid underlying");
        underlying = _underlying;
    }

    // @dev set the signer
    function setSigner(address[] memory signers_, bool[] memory isSigners_) public onlyManager {
        require(signers_.length == isSigners_.length, "mismatch length of signers");

        for (uint256 i = 0; i < signers_.length; i++) {
            require(signers_[i] != address(0), "zero signer");
            signers[signers_[i]] = isSigners_[i];
        }
    }

    // @dev set the minter role
    function setRole(bytes32 role, address account, bool isGrant) public onlyManager {
        if (role == MINTER_ROLE) {
            roles[account] = isGrant ? roles[account] | uint256(0x01) : roles[account] & ~uint256(0x01);
        } else if (role == BURNER_ROLE) {
            roles[account] = isGrant ? roles[account] | uint256(0x02) : roles[account] & ~uint256(0x02);
        } else if (role == DEPOSIT_ROLE) {
            roles[account] = isGrant ? roles[account] | uint256(0x04) : roles[account] & ~uint256(0x04);
        } else {
            revert("invalid role");
        }
        emit RoleSetted(role, account, msg.sender, isGrant);
    }

    // to handle the depoisted underlying asset
    function onDepositUnderlying(address from, address underlyingToken, uint256 underlyingAmount)
        internal
        override
        returns (uint256 sharesAmount, uint256 unitNav)
    {
        require(msg.value == 0, "not allowed to deposit native token");
        // transfer the underlying asset to the ceff wallet
        address ceffWallet = _portfolios.at(0);
        IERC20 assetToken = IERC20(underlyingToken);
        SafeERC20.safeTransferFrom(assetToken, from, ceffWallet, underlyingAmount);

        uint256 alignedAmount = alignDepositAmount(underlyingAmount, underlyingToken);
        require(alignedAmount >= minDepositAmount, "deposit amount too small");

        // calculate the shares amount
        unitNav = getUnitNav(settlementPeriod);
        require(unitNav > 0, "oops: zero unit nav");
        sharesAmount = alignedAmount * Precision / unitNav;

        // calculate the pending shares
        pendingShares[from][settlementPeriod] += sharesAmount;

        // emit the event
        emit PendingShares(from, settlementPeriod, sharesAmount);
    }
    // to handle the withdrawed underlying asset
    function onWithdrawUnderlying(address to, uint256 underlyingAmount)
        internal
        override
    {
        sendUnderlying(to, underlyingAmount);
    }

    // @dev confirm the shares
    // while the deposit passed KYT, then the user can confirm the shares
    function confirmShare(
        uint128 period,
        bytes32 txHash,
        uint256 sharesAmount,
        bytes memory signature
    )
        public
        whenNotPaused
    {
        require(sharesAmount > 0, "Invalid shares amount");
        require(pendingShares[msg.sender][period] >= sharesAmount, "not enough shares amount");
        require(!confirmedTx[txHash], "tx already confirmed");
        require(!refundedTx[txHash], "tx already refunded");

        // verify the signature
        bytes32 hash = _hashTypedDataV4(keccak256(abi.encode(
            CONFIRM_SHARE,
            period,
            txHash,
            msg.sender,
            sharesAmount
        )));
        address signer = ECDSA.recover(hash, signature);
        require(signers[signer], "Invalid signer");
        confirmedTx[txHash] = true;

        // sub the pending shares
        pendingShares[msg.sender][period] -= sharesAmount;
        // add the confirmed shares
        confirmedShares[msg.sender][period] += sharesAmount;

        // mint the shares
        _mint(msg.sender, sharesAmount);

        // emit the event
        emit ConfirmShares(msg.sender, txHash, period, sharesAmount);
    }
    // @dev refund the shares
    // if the deposit failed KYT, then the user can refund the shares
    // just burn the shares, the underlying asset will be returned to the user by Ceffu automatically
    function refundShare(
        uint128 period,
        bytes32 txHash,
        uint256 sharesAmount,
        bytes memory signature
    )
        public
        whenNotPaused
    {
        require(pendingShares[msg.sender][period] >= sharesAmount, "not enough shares amount");
        require(!refundedTx[txHash], "tx already refunded");
        require(!confirmedTx[txHash], "tx already confirmed");

        // verify the signature
        bytes32 hash = _hashTypedDataV4(keccak256(abi.encode(
            REFUND_SHARE,
            period,
            txHash,
            msg.sender,
            sharesAmount
        )));
        address signer = ECDSA.recover(hash, signature);
        require(signers[signer], "Invalid signer");
        refundedTx[txHash] = true;
        // sub the pending shares
        pendingShares[msg.sender][period] -= sharesAmount;

        // emit the event
        emit RefundShares(msg.sender, txHash, period, sharesAmount);
    }

    // @dev get the details of the balance
    struct BalanceDetails {
        uint256 totalShares;      // total shares of the user
        uint256 frozenShares;    // frozen shares of the user
        uint256 withdrawingShares; // withdrawing shares of the user
    }
    function getBalanceDetails(address user) public view returns (BalanceDetails memory) {
        BalanceDetails memory details;

        details.totalShares = balanceOf(user);
        details.frozenShares = frozenShares[user];
        details.withdrawingShares = getOngoingWithdrawShares(user);

        return details;
    }

    // @dev get current unit nav
    // @param period the period to get the unit nav, period should gte 1
    function getCurrentUnitNav() public view returns (uint256) {
        return getUnitNav(settlementPeriod);
    }

    // @dev method mint for chainlink CCIP
    function mint(address to, uint256 sharesAmount) public onlyMinter {
        _mint(to, sharesAmount);
        emit MinterMint(to, sharesAmount, msg.sender);
    }

    // @dev method burn for chainlinkCCIP
    function burn(uint256 sharesAmount) public {
        require(sharesAmount <= getUsableShares(msg.sender), "not enough shares amount");
        _burn(msg.sender, sharesAmount);
    }

    // @dev method burnFrom for chainlink CCIP
    function burnFrom(address from, uint256 sharesAmount) public onlyBurner {
        require(sharesAmount <= getUsableShares(from), "not enough shares amount");
        _burn(from, sharesAmount);
        emit BurnerBurn(from, sharesAmount, msg.sender);
    }

    // @dev method for Pendle or someone else to deposit without KYT.
    // just composit the deposit and confirm function.
    function directDeposit(address underlyingToken, uint256 underlyingAmount) public onlyDepositor {
        require(acceptUnderlying[underlyingToken] || underlyingToken == underlying);
                // transfer the underlying asset to the ceff wallet
        address ceffWallet = _portfolios.at(0);
        IERC20 assetToken = IERC20(underlyingToken);
        SafeERC20.safeTransferFrom(assetToken, msg.sender, ceffWallet, underlyingAmount);

        uint256 alignedAmount = alignDepositAmount(underlyingAmount, underlyingToken);
        require(alignedAmount >= minDepositAmount, "deposit amount too small");

        // calculate the shares amount
        uint256 unitNav = getUnitNav(settlementPeriod);
        require(unitNav > 0, "oops: zero unit nav");
        uint256 sharesAmount = alignedAmount * Precision / unitNav;

        // mint the shares
        _mint(msg.sender, sharesAmount);

        // emit the event
        emit DirectDeposit(msg.sender, settlementPeriod, underlyingToken, underlyingAmount, sharesAmount);
    }
}