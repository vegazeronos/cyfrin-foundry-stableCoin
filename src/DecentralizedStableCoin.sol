// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.19;

import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/*
 *@title DecentralizedStableCoin
 * @author Triady Bunawan
 * Collateral: Exogenous ETH & BTC
 * Minting: Algorithmic
 * Relative Stability: Pegged to USD 1:1
 * This is the contract that meant to be governed by DSCEngine. This contract is just ERC20 implementation of our stablecoin system
 */

contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    //error
    error DecentralizedStableCoin__AmountCannotBeZero();
    error DecentralizedStableCoin__BalanceMustBeGreaterThanAmount();
    error DecentralizedStableCoin__AddressToCannotBeZero();

    constructor() ERC20("Decentralized Stable Coin", "DSC") Ownable() {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralizedStableCoin__AmountCannotBeZero();
        }
        if (balance < _amount) {
            revert DecentralizedStableCoin__BalanceMustBeGreaterThanAmount();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoin__AddressToCannotBeZero();
        }
        if (_amount <= 0) {
            revert DecentralizedStableCoin__AmountCannotBeZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
