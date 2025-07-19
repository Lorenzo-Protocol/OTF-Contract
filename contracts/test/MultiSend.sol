// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract MultiSend is
    UUPSUpgradeable,
    OwnableUpgradeable
{

    constructor() {
        _disableInitializers();
    }

    receive() external payable {}

    function initialize(address owner) public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(owner);
    }


    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
    }

// 批量发送native token
    function multiSendNative(
        address[] calldata tos,
        uint256[] calldata amounts
    )
        public
        payable
    {
        require(tos.length == amounts.length, "length mismatch tos and amounts");

        uint256 totalReceived = msg.value;
        uint256 totalSent;
        uint256 len = tos.length;
        for (uint256 i; i < len; ) {
            require(tos[i] != address(0), "zero address");
            require(amounts[i] > 0, "zero amount");

            (bool success, bytes memory returndata) = payable(tos[i]).call{value: amounts[i]}("");
            require(success, string(returndata));

            totalSent += amounts[i];

            unchecked {
                ++i;
            }
        }

        // 退回多余的token
        if (totalReceived > totalSent) {
            payable(msg.sender).transfer(totalReceived - totalSent);
        }
    }

    // 批量发送erc20 token
    function multiSendERC20(
        address token,
        address[] calldata tos,
        uint256[] calldata amounts
    )
        public
    {
        require(tos.length == amounts.length, "length mismatch tos and amounts");

        uint256 len = tos.length;
        for (uint256 i; i < len; ) {
            SafeERC20.safeTransferFrom(IERC20(token), msg.sender, tos[i], amounts[i]);

            unchecked {
                ++i;
            }
        }
    }
}