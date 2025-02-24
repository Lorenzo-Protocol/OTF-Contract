// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;
import {IVault, YieldType} from "../intf/IVault.sol";
import {IFund} from "../intf/IFund.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

abstract contract CompositVault is UUPSUpgradeable, IFund {

}