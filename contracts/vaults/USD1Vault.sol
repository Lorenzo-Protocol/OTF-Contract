// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {Vault} from "./Vault.sol";
import {YieldType} from "../intf/IVault.sol";

contract USD1Vault is
    UUPSUpgradeable,
    EIP712Upgradeable,
    Vault
{
    using EnumerableSet for EnumerableSet.AddressSet;
    // users deposit usd1 to the vault, and get a pending shares waiting for KYT
    event PendingShares(address indexed user, uint128 indexed period, uint256 shares);
    // users confirm the shares after KYT passed
    event ConfirmShares (address indexed user, uint128 indexed period, uint256 shares);
    // users refund the shares after KYT failed
    event RefundShares  (address indexed user, uint128 indexed period, uint256 shares);

    bytes32 public constant CONFIRM_SHARE = keccak256("ConfirmShare(uint128 period,address user,uint256 sharesAmount,uint256 nonce)");
    bytes32 public constant REFUND_SHARE = keccak256("RefundShare(uint128 period,address user,uint256 sharesAmount,uint256 nonce)");

    mapping(address => mapping(uint128 => uint256)) public pendingShares; // user -> period -> pending shares
    mapping(address => bool) public signers; // signer -> is signer
    mapping(address => uint256) public confirmNonce; // user -> confirm nonce
    mapping(address => uint256) public refundNonce; // user -> refund nonce

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
        address underlying_,
        address[] memory portfolios_,
        uint256[] memory weights_,
        address cedefiManager_
    ) public initializer {
        require(underlying_ != address(0), "Invalid underlying");
        require(cedefiManager_ != address(0), "Invalid cedefi manager");
        require(portfolios_.length == weights_.length, "mismatch length of portfolios and weights");
        require(portfolios_.length == 1, "only accept one portfolio");

        __EIP712_init("USD1Vault", "1.0");
        __UUPSUpgradeable_init();
        __ERC20_init(name_, symbol_);

        cedefiManager = cedefiManager_;
        underlying = underlying_;

        settlementPeriod = 1;
        transferable = true;

        updatePortfolios(portfolios_, weights_);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyManager {}

    receive() external payable {
        revert("Not allowed to receive native token");
    }

    // @dev set the signer
    function setSigner(address[] memory signers_, bool[] memory isSigners_) public onlyManager {
        require(signers_.length == isSigners_.length, "mismatch length of signers");

        for (uint256 i = 0; i < signers_.length; i++) {
            signers[signers_[i]] = isSigners_[i];
        }
    }

    // to handle the depoisted underlying asset
    function onDepositUnderlying(address from, uint256 underlyingAmount)
        internal
        override
        returns (uint256 sharesAmount, uint256 unitNav)
    {
        // transfer the underlying asset to the ceff wallet
        address ceffWallet = _portfolios.at(0);
        IERC20 underlyingToken = IERC20(underlying);
        SafeERC20.safeTransferFrom(underlyingToken, from, ceffWallet, underlyingAmount);

        // calculate the shares amount
        unitNav = getUnitNav(settlementPeriod);
        sharesAmount = underlyingAmount * Precision / unitNav;

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
    function confirmShare(uint128 period, uint256 sharesAmount, bytes memory signature) public {
        require(sharesAmount > 0, "Invalid shares amount");
        require(pendingShares[msg.sender][period] >= sharesAmount, "not enough shares amount");

        // verify the signature
        bytes32 hash = _hashTypedDataV4(keccak256(abi.encode(
            CONFIRM_SHARE,
            period,
            msg.sender,
            sharesAmount,
            confirmNonce[msg.sender]
        )));
        address signer = ECDSA.recover(hash, signature);
        require(signers[signer], "Invalid signer");
        confirmNonce[msg.sender]++;

        // sub the pending shares
        pendingShares[msg.sender][period] -= sharesAmount;

        // mint the shares
        _mint(msg.sender, sharesAmount);

        // emit the event
        emit ConfirmShares(msg.sender, period, sharesAmount);
    }
    // @dev refund the shares
    // if the deposit failed KYT, then the user can refund the shares
    // just burn the shares, the underlying asset will be returned to the user by Ceffu automatically
    function refundShare(uint128 period, uint256 sharesAmount, bytes memory signature) public {
        require(pendingShares[msg.sender][period] >= sharesAmount, "not enough shares amount");

        // verify the signature
        bytes32 hash = _hashTypedDataV4(keccak256(abi.encode(
            REFUND_SHARE,
            period,
            msg.sender,
            sharesAmount,
            refundNonce[msg.sender]
        )));
        address signer = ECDSA.recover(hash, signature);
        require(signers[signer], "Invalid signer");
        refundNonce[msg.sender]++;
        // sub the pending shares
        pendingShares[msg.sender][period] -= sharesAmount;

        // emit the event
        emit RefundShares(msg.sender, period, sharesAmount);
    }
}