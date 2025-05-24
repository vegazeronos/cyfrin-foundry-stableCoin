// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/Mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address wethPriceFeed;
        address wbtcPriceFeed;
        address weth;
        address wbtc;
        uint256 deployerKey;
    }

    uint8 private constant DECIMAL = 8;
    int256 private constant ETH_USD_PRICE = 2000e8;
    int256 private constant BTC_USD_PRICE = 1000e8;
    uint256 private constant DEFAULT_PRIVATE_KEY_ANVIL =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    NetworkConfig public ActiveNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            ActiveNetworkConfig = getSepoliaEthConfig();
        } else {
            ActiveNetworkConfig = createOrGetAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            wethPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function createOrGetAnvilEthConfig() public returns (NetworkConfig memory) {
        if (ActiveNetworkConfig.wethPriceFeed != address(0)) {
            return ActiveNetworkConfig;
        }

        vm.startBroadcast();
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMAL, ETH_USD_PRICE);
        ERC20Mock wethMock = new ERC20Mock("WETH", "WETH", msg.sender, 1000e8);
        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(DECIMAL, BTC_USD_PRICE);
        ERC20Mock wbtcMock = new ERC20Mock("WBTC", "WBTC", msg.sender, 1000e8);
        vm.stopBroadcast();

        return NetworkConfig({
            wethPriceFeed: address(ethUsdPriceFeed),
            wbtcPriceFeed: address(btcUsdPriceFeed),
            weth: address(wethMock),
            wbtc: address(wbtcMock),
            deployerKey: DEFAULT_PRIVATE_KEY_ANVIL
        });
    }
}
