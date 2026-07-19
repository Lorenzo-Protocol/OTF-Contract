// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ISimpleVault} from "../intf/ISimpleVault.sol";
import {
    UUPSUpgradeable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {
    PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {
    ReentrancyGuardUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {
    ERC20Upgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Composes multiple SimpleVaults with fixed weights.
/// @dev SimpleVault merges withdraw requests by (msg.sender, period). Since this
///      contract is a single msg.sender, concurrent user redemptions in the same
///      child period are merged on-chain. Accounting:
///      1) child getUsableShares excludes pending redemptions from NAV / free balance;
///      2) userRequestShares / totalRequestShares track each user's share of a merged period;
///      3) each (vault, period) is pulled at most once, then users are paid pro-rata.
abstract contract ComposedVault is
    ERC20Upgradeable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    /// @dev Same scale as SimpleVault.Precision (1e18). Child unitNav uses
    ///      underlying-decimal base units; value = shares * unitNav / ONE.
    uint256 public constant ONE = 1e18;

    struct VaultConfig {
        address vault;
        uint256 weight;
    }

    error InvalidVault(address vault);
    error PendingWithdrawClaims();

    event SetUnderlying(address underlying);
    event SetVaults(VaultConfig[] vaults);
    event SetMinDepositAmount(uint256 amount);
    event Deposited(address indexed sender, uint256 amount, uint256 shares);
    event WithdrawRequested(
        address indexed sender,
        uint256 shares,
        address[] vaults,
        uint128[] reqIds
    );
    event Withdrawn(
        address indexed sender,
        uint256 amount,
        address[] vaults,
        uint128[] reqIds
    );

    VaultConfig[] public vaults;
    uint256 public minDepositAmount;
    address private _underlying;

    /// @dev Number of outstanding (user, vault, reqId) claim entries.
    uint256 public pendingClaimCount;

    // user => vault => reqId => shares
    mapping(address => mapping(address => mapping(uint128 => uint256)))
        public userRequestShares;
    // vault => reqId => total shares
    mapping(address => mapping(uint128 => uint256)) public totalRequestShares;
    // vault => reqId => whether underlying has been pulled
    mapping(address => mapping(uint128 => bool)) public periodPulled;
    // vault => reqId => total underlying pulled
    mapping(address => mapping(uint128 => uint256)) public totalPulledUnderlying;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory name,
        string memory symbol,
        address owner
    ) external initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(owner);
        __Pausable_init();
        __ReentrancyGuard_init();
        __ERC20_init(name, symbol);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function getUnderlying() external view returns (address) {
        return _underlying;
    }

    function setUnderlying(address underlying) external onlyOwner {
        require(underlying != address(0), "underlying is zero address");
        require(_underlying == address(0), "underlying is already set");
        _underlying = underlying;
        emit SetUnderlying(underlying);
    }

    /// @dev Only allowed when no composed shares and no outstanding withdraw claims.
    function setVaults(VaultConfig[] memory _vaults) external onlyOwner {
        require(totalSupply() == 0, "non-zero supply");
        if (pendingClaimCount != 0) {
            revert PendingWithdrawClaims();
        }

        uint256 totalWeight;
        uint256 length = _vaults.length;
        require(length > 0, "empty vaults");

        for (uint256 i; i < length; ++i) {
            address vaultAddr = _vaults[i].vault;
            require(vaultAddr.code.length > 0, InvalidVault(vaultAddr));

            ISimpleVault vault = ISimpleVault(vaultAddr);
            require(vault.getYieldType() != 0, InvalidVault(vaultAddr));
            require(
                _underlying == vault.getUnderlying(),
                "underlying mismatch"
            );
            require(_vaults[i].weight > 0, "zero weight");

            totalWeight += _vaults[i].weight;
        }
        require(totalWeight == ONE, "total weight must be ONE");

        delete vaults;
        for (uint256 i; i < length; ++i) {
            vaults.push(_vaults[i]);
        }
        emit SetVaults(_vaults);
    }

    function setMinDepositAmount(uint256 amount) external onlyOwner {
        minDepositAmount = amount;
        emit SetMinDepositAmount(amount);
    }

    /// @dev Deposit underlying into child vaults by weight, mint composed shares
    ///      using pre-deposit NAV.
    function deposit(
        IERC20 depositToken,
        uint256 amount
    ) external whenNotPaused nonReentrant {
        require(address(depositToken) == _underlying, "invalid deposit token");
        require(amount >= minDepositAmount, "lt min deposit amount");

        uint256 length = vaults.length;
        require(length > 0, "vaults not set");

        uint256 nav = getUnitNav();
        require(nav > 0, "invalid nav");

        SafeERC20.safeTransferFrom(
            depositToken,
            msg.sender,
            address(this),
            amount
        );

        uint256 distributed;
        for (uint256 i; i < length; ++i) {
            ISimpleVault vault = ISimpleVault(vaults[i].vault);
            uint256 depositAmount;
            if (i + 1 == length) {
                depositAmount = amount - distributed;
            } else {
                depositAmount = (amount * vaults[i].weight) / ONE;
                distributed += depositAmount;
            }
            if (depositAmount == 0) {
                continue;
            }
            SafeERC20.forceApprove(depositToken, address(vault), depositAmount);
            vault.deposit(address(depositToken), depositAmount);
        }

        uint256 shares = (amount * ONE) / nav;
        require(shares > 0, "zero shares");
        _mint(msg.sender, shares);
        emit Deposited(msg.sender, amount, shares);
    }

    /// @dev Burn composed shares and request proportional free child shares.
    function requestWithdraw(
        uint256 shares
    ) external whenNotPaused nonReentrant {
        require(shares > 0, "lt 0 shares");
        require(shares <= balanceOf(msg.sender), "insufficient shares");

        uint256 supply = totalSupply();
        require(shares <= supply, "insufficient supply");

        uint256 length = vaults.length;
        require(length > 0, "vaults not set");

        _burn(msg.sender, shares);

        address[] memory vaultsArray = new address[](length);
        uint128[] memory reqIds = new uint128[](length);
        for (uint256 i; i < length; ++i) {
            address vaultAddr = vaults[i].vault;
            ISimpleVault vault = ISimpleVault(vaultAddr);

            uint256 usableShares = vault.getUsableShares(address(this));
            uint256 withdrawShares = (usableShares * shares) / supply;
            require(withdrawShares > 0, "zero child shares");

            uint128 reqId = vault.requestWithdraw(withdrawShares);

            vaultsArray[i] = vaultAddr;
            reqIds[i] = reqId;

            if (userRequestShares[msg.sender][vaultAddr][reqId] == 0) {
                unchecked {
                    ++pendingClaimCount;
                }
            }
            userRequestShares[msg.sender][vaultAddr][reqId] += withdrawShares;
            totalRequestShares[vaultAddr][reqId] += withdrawShares;
        }

        emit WithdrawRequested(msg.sender, shares, vaultsArray, reqIds);
    }

    /// @dev Pull requested underlying from the vault.
    function _pullRequestedUnderlying(
        address _vault,
        uint128 _reqId
    ) internal returns (uint256) {
        ISimpleVault vault = ISimpleVault(_vault);
        IERC20 underlyingToken = IERC20(_underlying);

        uint256 balanceBefore = underlyingToken.balanceOf(address(this));
        vault.withdraw(_reqId);
        uint256 balanceAfter = underlyingToken.balanceOf(address(this));

        return balanceAfter - balanceBefore;
    }

    /// @dev Pull each child period once (merged SimpleVault requests), then pay
    ///      this user's pro-rata underlying from the pulled amount.
    function withdraw(
        address[] memory _vaults,
        uint128[] memory _reqIds
    ) external whenNotPaused nonReentrant {
        require(
            _vaults.length == _reqIds.length,
            "vaults and reqIds length mismatch"
        );
        require(_vaults.length > 0, "empty vaults");

        IERC20 underlyingToken = IERC20(_underlying);
        uint256 totalWithdrawAmount;

        uint256 length = _vaults.length;
        for (uint256 i; i < length; ++i) {
            address vaultAddr = _vaults[i];
            uint128 reqId = _reqIds[i];

            uint256 requestShares = userRequestShares[msg.sender][vaultAddr][
                reqId
            ];
            require(requestShares > 0, "zero user request shares");
            delete userRequestShares[msg.sender][vaultAddr][reqId];
            unchecked {
                --pendingClaimCount;
            }

            uint256 totalShares = totalRequestShares[vaultAddr][reqId];
            require(totalShares > 0, "zero total request shares");

            uint256 pulled;
            if (!periodPulled[vaultAddr][reqId]) {
                pulled = _pullRequestedUnderlying(vaultAddr, reqId);
                periodPulled[vaultAddr][reqId] = true;
                totalPulledUnderlying[vaultAddr][reqId] = pulled;
            } else {
                pulled = totalPulledUnderlying[vaultAddr][reqId];
            }

            totalWithdrawAmount += (requestShares * pulled) / totalShares;
        }

        require(totalWithdrawAmount > 0, "no withdraw amount");

        SafeERC20.safeTransfer(
            underlyingToken,
            msg.sender,
            totalWithdrawAmount
        );

        emit Withdrawn(msg.sender, totalWithdrawAmount, _vaults, _reqIds);
    }

    /// @dev Unit NAV in ONE scale. Pending child redeem shares are excluded via
    ///      getUsableShares.
    function getUnitNav() public view returns (uint256) {
        uint256 totalValue = totalAssets();
        uint256 supply = totalSupply();

        return supply > 0 ? (totalValue * ONE) / supply : ONE;
    }

    /// @dev Underlying-denominated value of free (non-pending) child shares.
    function totalAssets() public view returns (uint256) {
        uint256 totalValue;
        uint256 length = vaults.length;
        for (uint256 i; i < length; ++i) {
            address vaultAddr = vaults[i].vault;
            ISimpleVault vault = ISimpleVault(vaultAddr);
            uint256 unitNav = vault.getCurrentUnitNav();
            uint256 usableShares = vault.getUsableShares(address(this));
            totalValue += (usableShares * unitNav) / ONE;
        }
        return totalValue;
    }
}
