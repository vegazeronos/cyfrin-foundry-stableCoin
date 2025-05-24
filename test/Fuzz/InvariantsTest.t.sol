//apa yang tidak boleh berubah? apa yang harus jadi invariants?
// 1. total supply DSC minted tidak boleh lebih dari total collateral
// 2. redeemed collateral tidak boleh membuat health factor dibawah semestinya
// 3. burn dsc tidak boleh lebih dari dsc minted
// 4. health factor tidak boleh dibawah semestinya
// 5. getter view function cannot revert

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {console} from "forge-std/console.sol";
import {Handler} from "./Handler.t.sol";

contract InvariaOpenInvariantsTest is StdInvariant, Test {
    DeployDSC public deployer;
    DSCEngine public engine;
    DecentralizedStableCoin public dsc;
    HelperConfig public config;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external {
        deployer = new DeployDSC();
        (engine, dsc, config) = deployer.run();
        (,, weth, wbtc,) = config.ActiveNetworkConfig();
        //targetContract(address(engine));
        handler = new Handler(dsc, engine);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public {
        //dapetin total supply DSC dan total supply collateral
        uint256 totalSupplyDSC = dsc.totalSupply();
        uint256 totalSupplyWETH = IERC20(weth).balanceOf(address(engine));
        uint256 totalSupplyWBTC = IERC20(wbtc).balanceOf(address(engine));

        uint256 totalWETHValue = engine.getUsdValue(weth, totalSupplyWETH);
        uint256 totalWBTCValue = engine.getUsdValue(wbtc, totalSupplyWBTC);
        uint256 totalValue = totalWETHValue + totalWBTCValue;

        console.log("Total supply DSC: ", totalSupplyDSC);
        console.log("Value WETH: ", totalWETHValue);
        console.log("Value WBTC: ", totalWBTCValue);
        console.log("Total Value: ", totalValue);

        assert(totalValue >= totalSupplyDSC);
    }
}
