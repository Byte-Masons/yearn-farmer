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

/**
 * @dev Strategy to wrap and deposit in to a Yearn vault
 */
contract ReaperStrategyYearnFarmer is ReaperBaseStrategyv4 {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // 3rd-party contract addresses
    IYearnVault public yearnVault;
    IYearnVault public constant YV_OP = IYearnVault(0x7D2382b1f8Af621229d33464340541Db362B4907);
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
        _withdrawAll();
        _harvestCore();
        return balanceOfWant();
    }

    /**
     * @dev Hook run before harvest to claim rewards
     */
    function _beforeHarvestSwapSteps() internal override {
        stakingRewards.getReward();
        uint256 yvOpBalance = YV_OP.balanceOf((address(this)));
        if (yvOpBalance != 0) {
            bool isOpVault = address(yearnVault) == address(YV_OP);
            if (isOpVault) {
                _stake();
            } else {
                YV_OP.withdraw();
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
            IERC20Upgradeable(want).safeIncreaseAllowance(address(yearnVault), toReinvest);
            yearnVault.deposit(toReinvest);
            _stake();
        }
    }

    /**
     * @dev Withdraws funds and sends them back to the vault.
     */
    function _withdraw(uint256 _amount) internal override {
        uint256 withdrawable = MathUpgradeable.min(_amount, balanceOfPool());
        if (withdrawable != 0) {
            uint256 pricePerShare = yearnVault.pricePerShare();
            uint256 sharesToWithdraw = withdrawable * 1 ether / pricePerShare;
            if (sharesToWithdraw > 1) {
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
    }

    /**
     * @dev Exits fully out of Yearn vaults and staking contract
     */
    function _withdrawAll() internal {
        stakingRewards.exit();
        yearnVault.withdraw();
    }

    /**
     * @dev Function to calculate the total {want} held by the strat.
     * It takes in to account the free balance and the amount deposited
     * to the yearn vault and in the staking contract.
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
        return vaultShares * pricePerShare / 1 ether;
    }

    /**
     * @dev Stakes the Yearn vault tokens in the staking contract
     */
    function _stake() internal {
        uint256 toStake = yearnVault.balanceOf(address(this));
        yearnVault.increaseAllowance(address(stakingRewards), toStake);
        stakingRewards.stake(toStake);
    }
}
