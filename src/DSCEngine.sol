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

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {oracleLib} from "./libraries/Oracle.sol";

/*
 *@title DSCEngine
 * @author Triady Bunawan
 *
 * This token meant to be Pegged 1 token = 1dollar
 * This stablecoin has properties:
 * 1.Exogeneous Collateral
 * 2. Dollar Pegged
 * 3. Algorithmitically stable
 *
 * It is similiar to DAI with no governance, no fees, backed by WETH and WBTC
 *
 * Our DSC system is design to be "Overcollateral"
 *
 * @notice this contract is the core of the DSC System
 * @notice this contract is very loosely based on MakerDAO DSS (DAI) System
 * */

contract DSCEngine is ReentrancyGuard {
    //////////////////
    //error         //
    //////////////////
    error DSCEngine__NoZeroAmount();
    error DSCEngine__TokenAddressLengthIsNotSameWithPriceFeeds();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorIsOkay();
    error DSCEngine__HealthFactorNotImproved();

    //////////////////
    //type          //
    //////////////////

    using oracleLib for AggregatorV3Interface;

    ///////////////////////////
    //State Variable         //
    ///////////////////////////
    uint256 private constant ADDITIONAL_PRICE_FEED = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_TRESHOLD = 50; //200%  , need to be doubled the collateral to mint the DSC
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; //it means 10% bonus
    uint256 private constant LIQUIDATION_PERCENT = 100;

    mapping(address token => address priceFeeds) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDSCMinted) private s_userMintedAmount;

    address[] private s_collateralToken;
    DecentralizedStableCoin private immutable i_dsc;

    //////////////////
    //events        //
    //////////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(
        address indexed redeemFrom, address indexed redeemTo, address indexed token, uint256 amount
    );

    //////////////////
    //modifier      //
    //////////////////
    modifier amountCannotBeZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NoZeroAmount();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    //////////////////
    //function      //
    //////////////////
    constructor(address[] memory tokenAddress, address[] memory priceFeedAddress, address dscAddress) {
        if (tokenAddress.length != priceFeedAddress.length) {
            revert DSCEngine__TokenAddressLengthIsNotSameWithPriceFeeds();
        }
        for (uint256 i = 0; i < tokenAddress.length; i++) {
            s_priceFeeds[tokenAddress[i]] = priceFeedAddress[i];
            s_collateralToken.push(tokenAddress[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    //////////////////////
    //external function///
    //////////////////////

    /*
     * @notice this function will deposit and mint your dsc in one transaction
     * @param tokenCollateralAddress the address of the token to deposit as collateral
     * @param amountCollateral the amount of collateral to deposit
     * @param amountDscToMint the amount of Dsc to be mint
     *
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /*
     * @notice using CEI
     * @param tokenCollateralAddress the address of the token to deposit as collateral
     * @param amountCollateral the amount of collateral to deposit
     *
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        //check
        amountCannotBeZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        //effect
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        //interaction
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /*
     * @notice using CEI
     * @param tokenCollateralAddress the address of the token to deposit as collateral
     * @param amountCollateral the amount of collateral to deposit
     * @param amountDscToBurned the amount Dsc to burned
     * this function burn dsc and redeem collateral in one function
     *
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurned)
        external
    {
        burnDsc(amountDscToBurned);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    //redeem collateral
    //health factor need to be over 1 AFTER the amount of pulled
    //DRY : dont repeat yourself
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        amountCannotBeZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorBroken(msg.sender);
    }

    function burnDsc(uint256 amount) public amountCannotBeZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorBroken(msg.sender);
    }

    /*
     * @notice using CEI
     * @param amountDscToMint the amount of DSC sender want to mint
     * @notice they must have more collateral amount than minted amount
     */
    //check apakah collateral < mint amount
    function mintDsc(uint256 amountDscToMint) public amountCannotBeZero(amountDscToMint) nonReentrant {
        s_userMintedAmount[msg.sender] += amountDscToMint;
        _revertIfHealthFactorBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    /*
     * @notice using CEI
     * @param collateral the erc20 collateral address to liquidate from the user
     * @param user the user that their health factor is broken. Their healthFactor must be below MIN_HEALTH_FACTOR
     * @param debtToCover the amount Dsc to burned to improve the healtfactor
     * @notice you can partially liquidate a user
     * @notice you will get a liquidation bonus if you taking the user funds
     * @notice in order to this function to work, the collateral must be 200% overcollaterized
     * @notice 
     *
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        amountCannotBeZero(debtToCover)
        nonReentrant
    {
        //1. check the health factor, is it below min_health_factor? if yes, proceed
        uint256 startingHealthFactor = _healthFactor(user);
        if (startingHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsOkay();
        }
        //2. burn their DSC and take the collateral
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        //3. bonus 10% for those who liquidate
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PERCENT;

        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);
        //burn the dsc
        _burnDsc(debtToCover, user, msg.sender);
        uint256 endingHealthFactor = _healthFactor(user);
        if (startingHealthFactor >= endingHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorBroken(msg.sender);
    }

    function getHealthFactio() external view {}

    //////////////////////
    //internal function///
    //////////////////////

    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_userMintedAmount[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _getAccountInformation(address user)
        private
        returns (uint256 totalDSCMinted, uint256 collateralValueInUSD)
    {
        totalDSCMinted = s_userMintedAmount[user];
        collateralValueInUSD = getAccountCollateralValue(user);
    }

    /*
     * return how close user get to liquidation
     * if user get below 1, the user liquidated
     */
    function _healthFactor(address user) private returns (uint256) {
        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDSCMinted, collateralValueInUSD);
    }

    function _calculateHealthFactor(uint256 totalDSCMinted, uint256 collateralValueInUSD)
        internal
        pure
        returns (uint256)
    {
        if (totalDSCMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForTreshold = (collateralValueInUSD * LIQUIDATION_TRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForTreshold * PRECISION) / totalDSCMinted;
    }

    /*
    *   1. check healthfactor (have enough collateral or not)
    *   2. revert if it doesnt
    */
    function _revertIfHealthFactorBroken(address user) internal {
        if (_healthFactor(user) < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(_healthFactor(user));
        }
    }

    //////////////////////
    //public function  ///
    //////////////////////
    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_PRICE_FEED);
    }

    function getAccountCollateralValue(address user) public returns (uint256 totalCollateralValueInUsd) {
        //loop buat dapetin setiap collateral token, dapetin amount dari tiap token,
        //mapping ke harganya, dan dapetin harga dalam usd
        for (uint256 i = 0; i < s_collateralToken.length; i++) {
            address token = s_collateralToken[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
    }

    function getUsdValue(address token, uint256 amount) public returns (uint256) {
        //getting pricefeed from this function
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return ((uint256(price) * ADDITIONAL_PRICE_FEED) * amount) / PRECISION;
    }

    function getAccountInformation(address user)
        external
        returns (uint256 totalDSCMinted, uint256 collateralValueInUSD)
    {
        (totalDSCMinted, collateralValueInUSD) = _getAccountInformation(user);
    }

    function getUserMintedAmount(address user) external view returns (uint256) {
        return s_userMintedAmount[user];
    }

    function getPriceFeedAddress(address tokenAddress) external view returns (address) {
        return s_priceFeeds[tokenAddress];
    }

    function getCollateralDeposited(address user, address tokenCollateral) external view returns (uint256) {
        return s_collateralDeposited[user][tokenCollateral];
    }

    function getListedCollateralToken() external view returns (address[] memory) {
        return s_collateralToken;
    }
}
