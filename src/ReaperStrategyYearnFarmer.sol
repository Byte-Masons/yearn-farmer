// SPDX-License-Identifier: BUSL1.1

pragma solidity ^0.8.0;

import "vault-v2/interfaces/ISwapper.sol";
import {ReaperBaseStrategyv4} from "vault-v2/ReaperBaseStrategyv4.sol";
import {IStabilityPool} from "./interfaces/IStabilityPool.sol";
import {IPriceFeed} from "./interfaces/IPriceFeed.sol";
import {IVault} from "vault-v2/interfaces/IVault.sol";
import {AggregatorV3Interface} from "vault-v2/interfaces/AggregatorV3Interface.sol";
import {IVelodromePair} from "./interfaces/IVelodromePair.sol";
import {IStaticOracle} from "./interfaces/IStaticOracle.sol";
import {IUniswapV3Pool} from "./interfaces/IUniswapV3Pool.sol";
import {IERC20MetadataUpgradeable} from "oz-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {SafeERC20Upgradeable} from "oz-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {MathUpgradeable} from "oz-upgradeable/utils/math/MathUpgradeable.sol";
import {ReaperSwapper} from "vault-v2/ReaperSwapper.sol";

/**
 * @dev Strategy to compound rewards and liquidation collateral gains in the Ethos stability pool
 */
contract ReaperStrategyYearnFarmer is ReaperBaseStrategyv4 {
    using SafeERC20Upgradeable for IERC20MetadataUpgradeable;

    // 3rd-party contract addresses
    IStabilityPool public stabilityPool;
    IPriceFeed public priceFeed;
    IERC20MetadataUpgradeable public usdc;
    ExchangeSettings public exchangeSettings; // Holds addresses to use Velo, UniV3 and Bal through Swapper
    AggregatorV3Interface public sequencerUptimeFeed;
    IVelodromePair public veloUsdcErnPool;
    IUniswapV3Pool public uniV3UsdcErnPool;
    IStaticOracle public uniV3TWAP;

    uint256 public constant ETHOS_DECIMALS = 18; // Decimals used by ETHOS
    uint32 public constant CARDINALITY_PER_MINUTE = 30; // Optimism after bedrock update produces a block every 2 seconds
    uint256 public ernMinAmountOutBPS; // The max allowed slippage when trading in to ERN
    uint256 public compoundingFeeMarginBPS; // How much collateral value is lowered to account for the costs of swapping
    uint256 public veloUsdcErnQuoteGranularity; // How many samples to look at for Velo pool TWAP
    uint32 public uniV3TWAPPeriod; // How many seconds the uniV3 TWAP will look at
    TWAP public currentUsdcErnTWAP; // Which exchange is used to value ERN in terms of USDC
    ExchangeType public usdcToErnExchange; // Controls which exchange is used to swap USDC to ERN

    struct ExchangeSettings {
        address veloRouter;
        address balVault;
        address uniV3Router;
        address uniV2Router;
    }

    struct Pools {
        address stabilityPool;
        address veloUsdcErnPool;
        address uniV3UsdcErnPool;
    }

    struct Tokens {
        address want;
        address usdc;
    }

    enum TWAP {
        UniV3,
        VeloV2
    }

    error InvalidUsdcToErnExchange(uint256 exchangeEnum);
    error InvalidUsdcToErnTWAP(uint256 twapEnum);

    /**
     * @dev Initializes the strategy. Sets parameters, saves routes, and gives allowances.
     * @notice see documentation for each variable above its respective declaration.
     */
    function initialize(
        address _vault,
        address _swapper,
        address[] memory _strategists,
        address[] memory _multisigRoles,
        address[] memory _keepers,
        address _priceFeed,
        address _sequencerUptimeFeed,
        address _uniV3TWAP,
        ExchangeSettings calldata _exchangeSettings,
        Pools calldata _pools,
        Tokens calldata _tokens,
        TWAP _currentUsdcErnTWAP
    ) public initializer {
        require(_vault != address(0), "vault is 0 address");
        require(_swapper != address(0), "swapper is 0 address");
        require(_strategists.length != 0, "no strategists");
        require(_multisigRoles.length == 3, "invalid amount of multisig roles");
        require(_tokens.want != address(0), "want is 0 address");
        require(_priceFeed != address(0), "priceFeed is 0 address");
        require(_tokens.usdc != address(0), "usdc is 0 address");
        require(_sequencerUptimeFeed != address(0), "sequencerUptimeFeed is 0 address");
        require(_uniV3TWAP != address(0), "uniV3TWAP is 0 address");
        require(_exchangeSettings.veloRouter != address(0), "veloRouter is 0 address");
        require(_exchangeSettings.balVault != address(0), "balVault is 0 address");
        require(_exchangeSettings.uniV3Router != address(0), "uniV3Router is 0 address");
        require(_exchangeSettings.uniV2Router != address(0), "uniV2Router is 0 address");
        require(_pools.stabilityPool != address(0), "stabilityPool is 0 address");
        require(_pools.veloUsdcErnPool != address(0), "veloUsdcErnPool is 0 address");
        require(_pools.uniV3UsdcErnPool != address(0), "uniV3UsdcErnPool is 0 address");

        __ReaperBaseStrategy_init(_vault, _swapper, _tokens.want, _strategists, _multisigRoles, _keepers);
        stabilityPool = IStabilityPool(_pools.stabilityPool);
        priceFeed = IPriceFeed(_priceFeed);
        usdc = IERC20MetadataUpgradeable(_tokens.usdc);
        exchangeSettings = _exchangeSettings;

        ernMinAmountOutBPS = 9800;
        usdcToErnExchange = ExchangeType.VeloSolid;

        sequencerUptimeFeed = AggregatorV3Interface(_sequencerUptimeFeed);
        uniV3TWAP = IStaticOracle(_uniV3TWAP);
        veloUsdcErnPool = IVelodromePair(_pools.veloUsdcErnPool);
        uniV3UsdcErnPool = IUniswapV3Pool(_pools.uniV3UsdcErnPool);
        veloUsdcErnQuoteGranularity = 2;
        compoundingFeeMarginBPS = 9950;
        currentUsdcErnTWAP = _currentUsdcErnTWAP;
        updateUniV3TWAPPeriod(2);
    }

    /**
     * @dev Emergency function to quickly exit the position and return the funds to the vault
     */
    function _liquidateAllPositions() internal override returns (uint256 amountFreed) {
        _withdraw(type(uint256).max);
        _harvestCore();
        return balanceOfWant();
    }

    /**
     * @dev Hook run before harvest to claim rewards
     */
    function _beforeHarvestSwapSteps() internal override {
        _withdraw(0); // claim rewards
    }

    // Swap steps will:
    // 1. liquidate collateral rewards into USDC using the external Swapper (+ Chainlink oracles)
    // 2. liquidate oath rewards into USDC using the external swapper (with 0 minAmountOut)
    // As a final step, we need to convert the USDC into ERN using Velodrome's TWAP.
    // Since the external Swapper cannot support arbitrary TWAPs at this time, we use this hook so
    // we can calculate the minAmountOut ourselves and call the swapper directly.
    function _afterHarvestSwapSteps() internal override {
        uint256 usdcBalance = usdc.balanceOf(address(this));
        if (usdcBalance != 0) {
            uint256 expectedErnAmount = _getErnAmountForUsdc(usdcBalance);
            uint256 minAmountOut = (expectedErnAmount * ernMinAmountOutBPS) / PERCENT_DIVISOR;
            MinAmountOutData memory data =
                MinAmountOutData({kind: MinAmountOutKind.Absolute, absoluteOrBPSValue: minAmountOut});
            usdc.safeApprove(address(swapper), 0);
            usdc.safeIncreaseAllowance(address(swapper), usdcBalance);
            if (usdcToErnExchange == ExchangeType.Bal) {
                swapper.swapBal(address(usdc), want, usdcBalance, data, exchangeSettings.balVault);
            } else if (usdcToErnExchange == ExchangeType.VeloSolid) {
                swapper.swapVelo(address(usdc), want, usdcBalance, data, exchangeSettings.veloRouter);
            } else if (usdcToErnExchange == ExchangeType.UniV3) {
                swapper.swapUniV3(address(usdc), want, usdcBalance, data, exchangeSettings.uniV3Router);
            } else if (usdcToErnExchange == ExchangeType.UniV2) {
                swapper.swapUniV2(address(usdc), want, usdcBalance, data, exchangeSettings.uniV2Router);
            } else {
                revert InvalidUsdcToErnExchange(uint256(usdcToErnExchange));
            }
        }
    }

    /**
     * @dev Function that puts the funds to work.
     * It gets called whenever someone deposits in the strategy's vault contract
     * or when funds are reinvested in to the strategy.
     */
    function _deposit(uint256 toReinvest) internal override {
        if (toReinvest != 0) {
            stabilityPool.provideToSP(toReinvest);
        }
    }

    /**
     * @dev Withdraws funds and sends them back to the vault.
     */
    function _withdraw(uint256 _amount) internal override {
        if (_hasInitialDeposit(address(this))) {
            stabilityPool.withdrawFromSP(_amount);
        }
    }

    /**
     * @dev Function to calculate the total {want} held by the strat.
     * It takes into account both the funds in hand, the funds in the stability pool,
     * and also the balance of collateral tokens + USDC.
     */
    function _estimatedTotalAssets() internal override returns (uint256) {
        return balanceOfPoolUsingPriceFeed() + balanceOfWant();
    }

    /**
     * @dev Estimates the amount of ERN held in the stability pool and any
     * balance of collateral or USDC. The values are converted using oracles and
     * the Velodrome USDC-ERN TWAP and collateral+USDC value discounted slightly.
     */
    function balanceOfPool() public view override returns (uint256) {
        uint256 ernCollateralValue = getERNValueOfCollateralGain();
        return balanceOfPoolCommon(ernCollateralValue);
    }

    /**
     * @dev Estimates the amount of ERN held in the stability pool and any
     * balance of collateral or USDC. The values are converted using oracles and
     * the Velodrome USDC-ERN TWAP and collateral+USDC value discounted slightly.
     * Uses the Ethos price feed so backup oracles are used if chainlink fails.
     * Will likely not revert so can be used in harvest even if Chainlink is down.
     */
    function balanceOfPoolUsingPriceFeed() public returns (uint256) {
        uint256 ernCollateralValue = getERNValueOfCollateralGainUsingPriceFeed();
        return balanceOfPoolCommon(ernCollateralValue);
    }

    /**
     * @dev Shared logic for balanceOfPool functions
     */
    function balanceOfPoolCommon(uint256 _ernCollateralValue) public view returns (uint256) {
        uint256 depositedErn = stabilityPool.getCompoundedLUSDDeposit(address(this));
        uint256 adjustedCollateralValue = _ernCollateralValue * compoundingFeeMarginBPS / PERCENT_DIVISOR;

        return depositedErn + adjustedCollateralValue;
    }

    /**
     * @dev Calculates the estimated ERN value of collateral and USDC using Chainlink oracles
     * and the Velodrome USDC-ERN TWAP.
     */
    function getERNValueOfCollateralGain() public view returns (uint256 ernValueOfCollateral) {
        uint256 usdValueOfCollateralGain = getUSDValueOfCollateralGain();
        ernValueOfCollateral = getERNValueOfCollateralGainCommon(usdValueOfCollateralGain);
    }

    /**
     * @dev Calculates the estimated ERN value of collateral using the Ethos price feed, Chainlink oracle for USDC
     * and the Velodrome USDC-ERN TWAP.
     */
    function getERNValueOfCollateralGainUsingPriceFeed() public returns (uint256 ernValueOfCollateral) {
        uint256 usdValueOfCollateralGain = getUSDValueOfCollateralGainUsingPriceFeed();
        ernValueOfCollateral = getERNValueOfCollateralGainCommon(usdValueOfCollateralGain);
    }

    /**
     * @dev Shared logic for getERNValueOfCollateralGain functions.
     */
    function getERNValueOfCollateralGainCommon(uint256 _usdValueOfCollateralGain)
        public
        view
        returns (uint256 ernValueOfCollateral)
    {
        uint256 usdcValueOfCollateral = _getUsdcEquivalentOfUSD(_usdValueOfCollateralGain);
        uint256 usdcBalance = usdc.balanceOf(address(this));
        uint256 totalUsdcValue = usdcBalance + usdcValueOfCollateral;
        ernValueOfCollateral = _getErnAmountForUsdc(totalUsdcValue);
    }

    /**
     * @dev Calculates the estimated USD value of collateral gains using Chainlink oracles
     * {usdValueOfCollateralGain} is the USD value of all collateral in 18 decimals
     */
    function getUSDValueOfCollateralGain() public view returns (uint256 usdValueOfCollateralGain) {
        (address[] memory assets, uint256[] memory amounts) = stabilityPool.getDepositorCollateralGain(address(this));
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            uint256 amount;
            if (asset == address(usdc) || asset == want) {
                amount = amounts[i];
            } else {
                amount = amounts[i] + IERC20MetadataUpgradeable(asset).balanceOf(address(this));
            }
            if (amount != 0) {
                usdValueOfCollateralGain += _getUSDEquivalentOfCollateral(asset, amount);
            }
        }
    }

    /**
     * @dev Calculates the estimated USD value of collateral gains using the Ethos price feed
     * {usdValueOfCollateralGain} is the USD value of all collateral in 18 decimals
     */
    function getUSDValueOfCollateralGainUsingPriceFeed() public returns (uint256 usdValueOfCollateralGain) {
        (address[] memory assets, uint256[] memory amounts) = stabilityPool.getDepositorCollateralGain(address(this));
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            if (asset == address(usdc) || asset == want) {
                continue;
            }
            uint256 amount = amounts[i] + IERC20MetadataUpgradeable(asset).balanceOf(address(this));
            if (amount != 0) {
                usdValueOfCollateralGain += _getUSDEquivalentOfCollateralUsingPriceFeed(asset, amount);
            }
        }
    }

    /**
     * @dev Returns the {expectedErnAmount} for the specified {_usdcAmount} of USDC using either
     * VeloV2 or UniV3 TWAP depending on the {currentUsdcErnTWAP} setting.
     */
    function _getErnAmountForUsdc(uint256 _usdcAmount) internal view returns (uint256 expectedErnAmount) {
        if (_usdcAmount != 0) {
            if (currentUsdcErnTWAP == TWAP.VeloV2) {
                expectedErnAmount = veloUsdcErnPool.quote(address(usdc), _usdcAmount, veloUsdcErnQuoteGranularity);
            } else if (currentUsdcErnTWAP == TWAP.UniV3) {
                expectedErnAmount = getErnAmountForUsdcUniV3(uint128(_usdcAmount), uniV3TWAPPeriod);
            } else {
                revert InvalidUsdcToErnTWAP(uint256(currentUsdcErnTWAP));
            }
        }
    }

    /**
     * @dev Returns the {ernAmount} for the specified {_baseAmount} of USDC over a given {_period} (in seconds)
     * using the UniV3 TWAP.
     */
    function getErnAmountForUsdcUniV3(uint128 _baseAmount, uint32 _period) public view returns (uint256 ernAmount) {
        address[] memory pools = new address[](1);
        pools[0] = address(uniV3UsdcErnPool);
        uint256 quoteAmount =
            uniV3TWAP.quoteSpecificPoolsWithTimePeriod(_baseAmount, address(usdc), want, pools, _period);
        return quoteAmount;
    }

    /**
     * @dev Returns USD equivalent of {_amount} of {_collateral} with 18 digits of decimal precision.
     * The precision of {_amount} is whatever {_collateral}'s native decimals are (ex. 8 for wBTC)
     */
    function _getUSDEquivalentOfCollateral(address _collateral, uint256 _amount) internal view returns (uint256) {
        uint256 price = swapper.getChainlinkPriceTargetDigits(_collateral);
        return _getUSDEquivalentOfCollateralCommon(_collateral, _amount, price, ETHOS_DECIMALS);
    }

    /**
     * @dev Returns USD equivalent of {_amount} of {_collateral} with 18 digits of decimal precision.
     * The precision of {_amount} is whatever {_collateral}'s native decimals are (ex. 8 for wBTC)
     * This uses the price feed directly which has a Tellor backup oracle should Chainlink fail.
     * However it is not view so can only be used in none-view functions
     */
    function _getUSDEquivalentOfCollateralUsingPriceFeed(address _collateral, uint256 _amount)
        internal
        returns (uint256)
    {
        uint256 price = priceFeed.fetchPrice(_collateral);
        return _getUSDEquivalentOfCollateralCommon(_collateral, _amount, price, ETHOS_DECIMALS);
    }

    /**
     * @dev Shared logic for getUSDEquivalentOfCollateral functions
     */
    function _getUSDEquivalentOfCollateralCommon(
        address _collateral,
        uint256 _amount,
        uint256 _price,
        uint256 _priceDecimals
    ) internal view returns (uint256) {
        uint256 scaledAmount = _scaleToEthosDecimals(_amount, IERC20MetadataUpgradeable(_collateral).decimals());
        uint256 USDAssetValue = (scaledAmount * _price) / (10 ** _priceDecimals);
        return USDAssetValue;
    }

    /**
     * @dev Returns Usdc equivalent of {_amount} of USD with 6 digits of decimal precision.
     * The precision of {_amount} is 18 decimals
     */
    function _getUsdcEquivalentOfUSD(uint256 _amount) internal view returns (uint256) {
        uint256 usdcPrice18Decimals;
        try swapper.getChainlinkPriceTargetDigits(address(usdc)) returns (uint256 price) {
            usdcPrice18Decimals = price;
        } catch {
            usdcPrice18Decimals = 1 ether; // default to 1$
        }

        return (_amount * 10 ** uint256(usdc.decimals())) / usdcPrice18Decimals;
    }

    /**
     * @dev Check to ensure an initial deposit has been made in the stability pool
     * Which is a requirement to call withdraw.
     */
    function _hasInitialDeposit(address _user) internal view returns (bool) {
        return stabilityPool.deposits(_user).initialValue != 0;
    }

    /**
     * @dev Scales {_collAmount} given in {_collDecimals} to an 18 decimal amount (used by Ethos)
     */
    function _scaleToEthosDecimals(uint256 _collAmount, uint256 _collDecimals)
        internal
        pure
        returns (uint256 scaledColl)
    {
        scaledColl = _collAmount;
        if (_collDecimals > ETHOS_DECIMALS) {
            scaledColl = scaledColl / (10 ** (_collDecimals - ETHOS_DECIMALS));
        } else if (_collDecimals < ETHOS_DECIMALS) {
            scaledColl = scaledColl * (10 ** (ETHOS_DECIMALS - _collDecimals));
        }
    }

    /**
     * @dev Scales {_collAmount} given in 18 decimals to an amount in {_collDecimals}
     */
    function _scaleToCollateralDecimals(uint256 _collAmount, uint256 _collDecimals)
        internal
        pure
        returns (uint256 scaledColl)
    {
        scaledColl = _collAmount;
        if (_collDecimals > ETHOS_DECIMALS) {
            scaledColl = scaledColl * (10 ** (_collDecimals - ETHOS_DECIMALS));
        } else if (_collDecimals < ETHOS_DECIMALS) {
            scaledColl = scaledColl / (10 ** (ETHOS_DECIMALS - _collDecimals));
        }
    }

    /**
     * @dev Updates the {ernMinAmountOutBPS} which is the minimum amount accepted in a USDC->ERN/want swap.
     * In BPS so 9500 would allow a 5% slippage.
     */
    function updateErnMinAmountOutBPS(uint256 _ernMinAmountOutBPS) external {
        _atLeastRole(STRATEGIST);
        require(_ernMinAmountOutBPS > 8000 && _ernMinAmountOutBPS < PERCENT_DIVISOR, "Invalid slippage value");
        ernMinAmountOutBPS = _ernMinAmountOutBPS;
    }

    /**
     * @dev Sets the exchange used to swap USDC to ERN/want (can be Velo, UniV3, Balancer)
     */
    function setUsdcToErnExchange(ExchangeType _exchange) external {
        _atLeastRole(STRATEGIST);
        usdcToErnExchange = _exchange;
    }

    /**
     * @dev Updates the granularity used to check Velodrome TWAP (larger value looks at more samples/longer time)
     */
    function updateVeloUsdcErnQuoteGranularity(uint256 _veloUsdcErnQuoteGranularity) external {
        _atLeastRole(STRATEGIST);
        require(_veloUsdcErnQuoteGranularity >= 2 && _veloUsdcErnQuoteGranularity <= 10, "Invalid granularity value");
        veloUsdcErnQuoteGranularity = _veloUsdcErnQuoteGranularity;
    }

    /**
     * @dev Updates the value used to adjust the value of collateral down slightly (between 0-2%)
     * To account for swap fees and slippage to go from collateral to want
     */
    function updateCompoundingFeeMarginBPS(uint256 _compoundingFeeMarginBPS) external {
        _atLeastRole(GUARDIAN);
        require(
            _compoundingFeeMarginBPS > 9800 && _compoundingFeeMarginBPS <= PERCENT_DIVISOR,
            "Invalid compoundingFeeMarginBPS value"
        );
        compoundingFeeMarginBPS = _compoundingFeeMarginBPS;
    }

    /**
     * @dev Sets the period (in seconds) used to query the UniV3 TWAP
     * The pool itself has a {currentCardinality} that must be set before
     * to support a given period by calling increaseObservationCardinalityNext
     * on the UniV3 pool.
     */
    function updateUniV3TWAPPeriod(uint32 _uniV3TWAPPeriod) public {
        _atLeastRole(ADMIN);
        (,,, uint16 currentCardinality,,,) = uniV3UsdcErnPool.slot0();
        uint32 maxPeriod = uint32(currentCardinality) * 60 / CARDINALITY_PER_MINUTE;
        require(_uniV3TWAPPeriod <= maxPeriod, "Pool needs a higher cardinality to support the period");
        uniV3TWAPPeriod = _uniV3TWAPPeriod;
    }

    /**
     * @dev Sets which TWAP will be used to price USDC-ERN. Can currently
     * be either UniV3 or VeloV2.
     */
    function updateCurrentUsdcErnTWAP(TWAP _currentUsdcErnTWAP) external {
        _atLeastRole(GUARDIAN);
        currentUsdcErnTWAP = _currentUsdcErnTWAP;
    }
}