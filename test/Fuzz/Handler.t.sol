//handler adalah cara untuk memberi tau fuzz test, kalau ada aturan yang harus dilalui untuk ngetes contract, sehingga fuzz test tidak acak acak ngetes kontraknya, melainkan mengikuti aturan yang ada sehingga contract bisa di test dengan baik... contoh, jika fuzz test dilakukan tanpa handler, fuzz test bisa melakukan apa saja, misal pertama kali fungsi yang ditest adalah "liquidate", tentu hasilnya akan error karena, belumj ada user yang ngutang DSC atau deposit collateral... contoh lagi, jika tanpa handler, foundry akan test sembarang, dan mungkin langsung test minting.... ini juga akan gagal, karena sblm minting, user harus deposit something dlu, yaitu deposit collateral (WETH atau WBTC)

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../Mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    ERC20Mock weth;
    ERC20Mock wbtc;
    MockV3Aggregator public EthUsdPriceFeed;

    uint96 public constant MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DecentralizedStableCoin _dsc, DSCEngine _engine) {
        dsc = _dsc;
        engine = _engine;

        address[] memory collateralToken;
        collateralToken = engine.getListedCollateralToken();
        weth = ERC20Mock(collateralToken[0]);
        wbtc = ERC20Mock(collateralToken[1]);

        EthUsdPriceFeed = MockV3Aggregator(engine.getPriceFeedAddress(address(weth)));
    }

    //1. deposit collateral
    function mintAndDepositCollateral(uint256 collateralSeed, uint256 amountDeposit) public {
        ERC20Mock collateralAddr = _getCollateralAddress(collateralSeed);
        amountDeposit = bound(amountDeposit, 1, MAX_DEPOSIT_SIZE);
        vm.startPrank(msg.sender);
        collateralAddr.mint(msg.sender, amountDeposit);
        collateralAddr.approve(address(engine), amountDeposit); //we need to approve the protocol, to deposit collateral (protocol = engine (dscEngine))
        engine.depositCollateral(address(collateralAddr), amountDeposit);
        vm.stopPrank();
    }

    function mintDsc(uint256 amount) public {
        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = engine.getAccountInformation(msg.sender);
        int256 maxAmountToBeMinted = int256((collateralValueInUSD / 2) - totalDSCMinted);
        if (maxAmountToBeMinted < 0) {
            return;
        }
        amount = bound(amount, 0, uint256(maxAmountToBeMinted));
        if (amount == 0) {
            return;
        }
        vm.startPrank(msg.sender);
        engine.mintDsc(amount);
        vm.stopPrank();
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountDeposit) public {
        vm.startPrank(msg.sender);
        ERC20Mock collateralAddr = _getCollateralAddress(collateralSeed);
        uint256 maximalAmountToRedeem = engine.getCollateralDeposited(msg.sender, address(collateralAddr));
        amountDeposit = bound(amountDeposit, 0, maximalAmountToRedeem);
        if (amountDeposit == 0) {
            return;
        }
        engine.redeemCollateral(address(collateralAddr), amountDeposit);
        vm.stopPrank();
    }

    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceEth = int256(uint256(newPrice));
    //     EthUsdPriceFeed.updateAnswer(newPriceEth);
    // }

    function _getCollateralAddress(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }
}
