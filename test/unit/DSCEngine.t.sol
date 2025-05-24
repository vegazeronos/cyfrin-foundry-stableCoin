//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;
    address ethPriceFeed;
    address btcPriceFeed;
    address weth;
    address USER = makeAddr("user");
    uint256 public constant COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 100 ether;
    uint256 public constant AMOUNT_DSC = 100 ether;

    event CollateralRedeemed(
        address indexed redeemFrom, address indexed redeemTo, address indexed token, uint256 amount
    );

    function setUp() public {
        deployer = new DeployDSC();
        (engine, dsc, config) = deployer.run();
        (ethPriceFeed, btcPriceFeed, weth,,) = config.ActiveNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    ///////////////////////////
    //Constructor Test     ///
    /////////////////////////
    address[] tokenAddresses;
    address[] priceFeedsAddresses;

    modifier pushTokenAndPriceFeedsAddreses() {
        tokenAddresses.push(weth);
        priceFeedsAddresses.push(ethPriceFeed);
        priceFeedsAddresses.push(btcPriceFeed);
        _;
    }

    function testRevertIfLengthAddressIsNotTheSameAsPriceFeed() public pushTokenAndPriceFeedsAddreses {
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressLengthIsNotSameWithPriceFeeds.selector);
        new DSCEngine(tokenAddresses, priceFeedsAddresses, address(dsc));
    }

    ////////////////////////
    //price Test        ///
    //////////////////////
    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
        assertEq(actualUsd, expectedUsd);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        uint256 expectedEth = 0.05 ether;
        uint256 actualEth = engine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(actualEth, expectedEth);
    }

    //////////////////////////////
    //depositcollateral test    //
    /////////////////////////////
    function testRevertIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NoZeroAmount.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("Ran Token", "RAN", USER, COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        engine.depositCollateral(address(ranToken), COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), COLLATERAL);
        engine.depositCollateral(weth, COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier mintDsc() {
        vm.startPrank(USER);
        engine.mintDsc(AMOUNT_DSC);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = engine.getAccountInformation(USER);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(weth, collateralValueInUSD);
        assertEq(expectedTotalDscMinted, totalDSCMinted);
        assertEq(COLLATERAL, expectedDepositAmount);
    }

    function testCanDepositCollateralWithoutMinting() public depositedCollateral {
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock randToken = new ERC20Mock("RAN", "RAN", USER, 100e18);
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__NotAllowedToken.selector, address(randToken)));
        engine.depositCollateral(address(randToken), COLLATERAL);
        vm.stopPrank();
    }

    ////////////////////////////////////////
    //redeem collateral and burn test    //
    //////////////////////////////////////

    function testRedeemCollateralForDscZeroCollateralReverts()
        public
        pushTokenAndPriceFeedsAddreses
        depositedCollateral
    {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NoZeroAmount.selector);
        engine.redeemCollateralForDsc(weth, AMOUNT_DSC, 0);
        vm.stopPrank();
    }

    function testRedeemCollateralZeroCollateralReverts() public pushTokenAndPriceFeedsAddreses depositedCollateral {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NoZeroAmount.selector);
        engine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testBurnRevertIfAmountIsZero() public depositedCollateral {
        //arrange
        vm.startPrank(USER);
        //act assert
        vm.expectRevert(DSCEngine.DSCEngine__NoZeroAmount.selector);
        engine.burnDsc(0);
        vm.stopPrank();
    }

    function testEmitCollateralRedeemed() public depositedCollateral {
        vm.expectEmit(true, true, true, true);
        emit CollateralRedeemed(USER, USER, weth, COLLATERAL);
        vm.startPrank(USER);
        engine.redeemCollateral(weth, COLLATERAL);
        vm.stopPrank();
    }

    ///////////////////////
    //liquidate test    //
    /////////////////////

    //////////////////
    //mint test    //
    ////////////////

    ///////////////////////////////
    //get Health Factor test    //
    /////////////////////////////
}
