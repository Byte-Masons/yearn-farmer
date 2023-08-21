// SPDX-License-Identifier: BUSL1.1

pragma solidity ^0.8.0;

import "vault-v2/interfaces/ISwapper.sol";
import {ReaperBaseStrategyv4} from "vault-v2/ReaperBaseStrategyv4.sol";
import {IVault} from "vault-v2/interfaces/IVault.sol";
import {IYearnVault} from "./interfaces/IYearnVault.sol";
import {IStakingRewards} from "./interfaces/IStakingRewards.sol";
import {IERC20Upgradeable} from "oz-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "oz-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {MathUpgradeable} from "oz-upgradeable/utils/math/MathUpgradeable.sol";
import {ReaperSwapper} from "vault-v2/ReaperSwapper.sol";
import "forge-std/console.sol";

/**
 * @dev Strategy to wrap and deposit in to a Yearn vault
 */
contract ReaperStrategyYearnFarmer is ReaperBaseStrategyv4 {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // 3rd-party contract addresses
    IYearnVault public yearnVault;
    IStakingRewards public stakingRewards;

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
        address _yearnVault,
        address _stakingRewards
    ) public initializer {
        require(_vault != address(0), "vault is 0 address");
        require(_swapper != address(0), "swapper is 0 address");
        require(_strategists.length != 0, "no strategists");
        require(_multisigRoles.length == 3, "invalid amount of multisig roles");
        require(_yearnVault != address(0), "yearnVault is 0 address");
        require(_stakingRewards != address(0), "stakingRewards is 0 address");
        yearnVault = IYearnVault(_yearnVault);
        stakingRewards = IStakingRewards(_stakingRewards);
        require(stakingRewards.stakingToken() == _yearnVault, "stakingRewards contract does not match vault");
        address want = yearnVault.token();
        __ReaperBaseStrategy_init(_vault, _swapper, want, _strategists, _multisigRoles, _keepers);
    }

    /**
     * @dev Emergency function to quickly exit the position and return the funds to the vault
     */
    function _liquidateAllPositions() internal override returns (uint256 amountFreed) {
        // _withdraw(type(uint256).max);
        // _harvestCore();
        // return balanceOfWant();
    }

    /**
     * @dev Hook run before harvest to claim rewards
     */
    function _beforeHarvestSwapSteps() internal override {
        // _withdraw(0); // claim rewards
    }

    // Swap steps will:
    // 1. liquidate collateral rewards into USDC using the external Swapper (+ Chainlink oracles)
    // 2. liquidate oath rewards into USDC using the external swapper (with 0 minAmountOut)
    // As a final step, we need to convert the USDC into ERN using Velodrome's TWAP.
    // Since the external Swapper cannot support arbitrary TWAPs at this time, we use this hook so
    // we can calculate the minAmountOut ourselves and call the swapper directly.
    function _afterHarvestSwapSteps() internal override {
        // uint256 usdcBalance = usdc.balanceOf(address(this));
        // if (usdcBalance != 0) {
        //     uint256 expectedErnAmount = _getErnAmountForUsdc(usdcBalance);
        //     uint256 minAmountOut = (expectedErnAmount * ernMinAmountOutBPS) / PERCENT_DIVISOR;
        //     MinAmountOutData memory data =
        //         MinAmountOutData({kind: MinAmountOutKind.Absolute, absoluteOrBPSValue: minAmountOut});
        //     usdc.safeApprove(address(swapper), 0);
        //     usdc.safeIncreaseAllowance(address(swapper), usdcBalance);
        //     if (usdcToErnExchange == ExchangeType.Bal) {
        //         swapper.swapBal(address(usdc), want, usdcBalance, data, exchangeSettings.balVault);
        //     } else if (usdcToErnExchange == ExchangeType.VeloSolid) {
        //         swapper.swapVelo(address(usdc), want, usdcBalance, data, exchangeSettings.veloRouter);
        //     } else if (usdcToErnExchange == ExchangeType.UniV3) {
        //         swapper.swapUniV3(address(usdc), want, usdcBalance, data, exchangeSettings.uniV3Router);
        //     } else if (usdcToErnExchange == ExchangeType.UniV2) {
        //         swapper.swapUniV2(address(usdc), want, usdcBalance, data, exchangeSettings.uniV2Router);
        //     } else {
        //         revert InvalidUsdcToErnExchange(uint256(usdcToErnExchange));
        //     }
        // }
    }

    /**
     * @dev Function that puts the funds to work.
     * It gets called whenever someone deposits in the strategy's vault contract
     * or when funds are reinvested in to the strategy.
     */
    function _deposit(uint256 toReinvest) internal override {
        if (toReinvest != 0) {
            console.log("toReinvest: ", toReinvest);
            IERC20Upgradeable(want).safeIncreaseAllowance(address(yearnVault), toReinvest);
            yearnVault.deposit(toReinvest);
            uint256 toStake = yearnVault.balanceOf(address(this));
            yearnVault.increaseAllowance(address(stakingRewards), toStake);
            stakingRewards.stake(toStake);
        }
    }

    /**
     * @dev Withdraws funds and sends them back to the vault.
     */
    function _withdraw(uint256 _amount) internal override {
        console.log("withdraw _amount: ", _amount);
        console.log("balanceOfPool(): ", balanceOfPool());
        uint256 withdrawable = MathUpgradeable.min(_amount, balanceOfPool());
        if (withdrawable != 0) {
            console.log("withdrawable: ", withdrawable);
            uint256 pricePerShare = yearnVault.pricePerShare();
            console.log("pricePerShare: ", pricePerShare);
            uint256 sharesToWithdraw = withdrawable * 1 ether / pricePerShare;
            console.log("sharesToWithdraw: ", sharesToWithdraw);
            uint256 unstakedVaultShares = yearnVault.balanceOf(address(this));
            if (unstakedVaultShares < sharesToWithdraw) {
                uint256 sharesToUnstake = sharesToWithdraw - unstakedVaultShares;
                stakingRewards.withdraw(sharesToUnstake);
            }
            unstakedVaultShares = yearnVault.balanceOf(address(this));
            sharesToWithdraw = MathUpgradeable.min(unstakedVaultShares, sharesToWithdraw);
            yearnVault.withdraw(sharesToWithdraw);
        }
    }

    /**
     * @dev Function to calculate the total {want} held by the strat.
     * It takes into account both the funds in hand, the funds in the stability pool,
     * and also the balance of collateral tokens + USDC.
     */
    function _estimatedTotalAssets() internal override returns (uint256) {
        return balanceOfPool() + balanceOfWant();
    }

    /**
     * @dev Estimates the amount of want held in the Yearn vault or 
     * staking contract.
     */
    function balanceOfPool() public view override returns (uint256) {
        uint256 unstakedVaultShares = yearnVault.balanceOf(address(this));
        uint256 stakedVaultShares = stakingRewards.balanceOf(address(this));
        uint256 vaultShares = unstakedVaultShares + stakedVaultShares;
        uint256 pricePerShare = yearnVault.pricePerShare();
        // console.log("vaultShares: ", vaultShares);
        // console.log("pricePerShare: ", pricePerShare);
        // console.log("balanceOfPool: ", vaultShares * pricePerShare / 1 ether);
        return vaultShares * pricePerShare / 1 ether;
    }
}
