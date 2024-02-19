// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "src/ReaperStrategyYearnFarmer.sol";
import "vault-v2/ReaperSwapper.sol";
import "vault-v2/ReaperVaultV2.sol";
import "vault-v2/ReaperBaseStrategyv4.sol";
import "vault-v2/interfaces/ISwapper.sol";
import {IYearnVault} from "../src/interfaces/IYearnVault.sol";
import {IStakingRewards} from "../src/interfaces/IStakingRewards.sol";
import {ERC1967Proxy} from "oz/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Upgradeable} from "oz-upgradeable/token/ERC20/IERC20Upgradeable.sol";

contract ReaperStrategyYearnFarmerTest is Test {
    using stdStorage for StdStorage;
    // Fork Identifier

    uint256 public optimismFork;

    // Registry
    address public treasuryAddress = 0xeb9C9b785aA7818B2EBC8f9842926c4B9f707e4B;
    address public veloRouter = 0xa062aE8A9c5e11aaA026fc2670B0D65cCc8B2858;
    address public veloFactoryV1 = 0x25CbdDb98b35ab1FF77413456B31EC81A6B6B746;
    address public veloFactoryV2Default = 0xF1046053aa5682b4F9a81b5481394DA16BE5FF5a;
    address public balVault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address public uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public uniV2Router = 0xbeeF000000000000000000000000000000000000; // Any non-0 address when UniV2 router does not exist

    address public wethYearnVault = 0x5B977577Eb8a480f63e11FC615D6753adB8652Ae;
    address public usdcYearnVault = 0xaD17A225074191d5c8a37B50FdA1AE278a2EE6A2;

    address public wethStakingRewards = 0xE35Fec3895Dcecc7d2a91e8ae4fF3c0d43ebfFE0;
    address public usdcStakingRewards = 0xB2c04C55979B6CA7EB10e666933DE5ED84E6876b;

    address public superAdminAddress = 0x9BC776dBb134Ef9D7014dB1823Cd755Ac5015203;
    address public adminAddress = 0xeb9C9b785aA7818B2EBC8f9842926c4B9f707e4B;
    address public guardianAddress = 0xb0C9D5851deF8A2Aac4A23031CA2610f8C3483F9;

    address public wethAddress = 0x4200000000000000000000000000000000000006;
    address public wbtcAddress = 0x68f180fcCe6836688e9084f035309E29Bf0A2095;
    address public opAddress = 0x4200000000000000000000000000000000000042;
    address public usdcAddress = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;

    address public strategistAddr = 0x1A20D7A31e5B3Bc5f02c8A146EF6f394502a10c4;
    address public wantHolderAddr = strategistAddr;

    address[] public keepers = [
        0xe0268Aa6d55FfE1AA7A77587e56784e5b29004A2,
        0x34Df14D42988e4Dc622e37dc318e70429336B6c5,
        0x73C882796Ea481fe0A2B8DE499d95e60ff971663,
        0x36a63324edFc157bE22CF63A6Bf1C3B49a0E72C0,
        0x9a2AdcbFb972e0EC2946A342f46895702930064F,
        0x7B540a4D24C906E5fB3d3EcD0Bb7B1aEd3823897,
        0x8456a746e09A18F9187E5babEe6C60211CA728D1,
        0x55a078AFC2e20C8c20d1aa4420710d827Ee494d4,
        0x5241F63D0C1f2970c45234a0F5b345036117E3C2,
        0xf58d534290Ce9fc4Ea639B8b9eE238Fe83d2efA6,
        0x5318250BD0b44D1740f47a5b6BE4F7fD5042682D,
        0x33D6cB7E91C62Dd6980F16D61e0cfae082CaBFCA,
        0x51263D56ec81B5e823e34d7665A1F505C327b014,
        0x87A5AfC8cdDa71B5054C698366E97DB2F3C2BC2f
    ];

    bytes32 public constant KEEPER = keccak256("KEEPER");

    address[] public strategists = [strategistAddr];
    address[] public multisigRoles = [superAdminAddress, adminAddress, guardianAddress];

    // Initialized during set up
    string public vaultName = "Yearn farmer Vault";
    string public vaultSymbol = "rf-yv-WETH";
    uint256 public vaultTvlCap = type(uint256).max;

    ISwapper public swapper;

    struct BaseConfig {
        address wantAddress;
        address yearnVault;
        address stakingRewards;
        bool shouldStake;
        uint256 startingBalance;
    }

    struct VaultAndStratConfig {
        BaseConfig base;
        ERC20 want;
        ReaperVaultV2 vault;
        ReaperStrategyYearnFarmer strategy;
    }

    VaultAndStratConfig[] public configs;
    BaseConfig[] public baseConfigs;

    uint256 public feeBPS = 1000;
    uint256 public allocation = 10_000;

    function setUp() public {
        // Forking
        string memory rpc = vm.envString("RPC");
        optimismFork = vm.createSelectFork(rpc, 107994026);
        assertEq(vm.activeFork(), optimismFork);

        //Setting up swapper
        ReaperSwapper swapperImpl = new ReaperSwapper();
        ERC1967Proxy swapperProxy = new ERC1967Proxy(address(swapperImpl), "");
        ReaperSwapper wrappedSwapperProxy = ReaperSwapper(address(swapperProxy));
        wrappedSwapperProxy.initialize(strategists, guardianAddress, superAdminAddress);
        swapper = ISwapper(address(swapperProxy));

        
        vm.startPrank(superAdminAddress);
        swapper.updateTokenAggregator(wethAddress, 0x13e3Ee699D1909E989722E753853AE30b17e08c5, 172800);
        swapper.updateTokenAggregator(opAddress, 0x0D276FC14719f9292D5C1eA2198673d1f4269246, 172800);
        vm.stopPrank();

        address[] memory opWethPath = new address[](2);
        opWethPath[0] = opAddress;
        opWethPath[1] = wethAddress;

        uint24[] memory opWethFees = new uint24[](1);
        opWethFees[0] = 3000;
        UniV3SwapData memory opWethSwapData = UniV3SwapData({path: opWethPath, fees: opWethFees});
        swapper.updateUniV3SwapPath(opAddress, wethAddress, uniV3Router, opWethSwapData);


        //Setting up strategies
        baseConfigs.push(
            BaseConfig({
                wantAddress: usdcAddress,
                yearnVault: usdcYearnVault,
                stakingRewards: usdcStakingRewards,
                shouldStake: true,
                startingBalance: 10_000_000
            })
        );

        baseConfigs.push(
            BaseConfig({
                wantAddress: wethAddress,
                yearnVault: wethYearnVault,
                stakingRewards: wethStakingRewards,
                shouldStake: true,
                startingBalance: 100
            })
        );

        // ---------------------------------

        for (uint256 index = 0; index < baseConfigs.length; index++) {
            BaseConfig memory baseConfig = baseConfigs[index];

            ReaperVaultV2 vault = new ReaperVaultV2(
                baseConfig.wantAddress,
                vaultName, 
                vaultSymbol, 
                vaultTvlCap, 
                treasuryAddress, 
                strategists, 
                multisigRoles
            );

            ReaperStrategyYearnFarmer implementation = new ReaperStrategyYearnFarmer();
            ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), "");
            ReaperStrategyYearnFarmer strategy = ReaperStrategyYearnFarmer(address(proxy));

            strategy.initialize(
                address(vault),
                address(swapper),
                strategists,
                multisigRoles,
                keepers,
                address(baseConfig.yearnVault),
                address(baseConfig.stakingRewards),
                baseConfig.shouldStake
            );

            vault.addStrategy(address(strategy), feeBPS, allocation);

            vm.prank(wantHolderAddr);
            ERC20 want = ERC20(baseConfig.wantAddress);
            want.approve(address(vault), type(uint256).max);
            deal({token: baseConfig.wantAddress, to: wantHolderAddr, give: _toWant(baseConfig.startingBalance, baseConfig.wantAddress)});

            setUpSwapPaths(strategy);

            configs.push(
                VaultAndStratConfig(baseConfig, want, vault, strategy)
            );
        }
    }

    function setUpSwapPaths(ReaperStrategyYearnFarmer strategy) public {
        ReaperBaseStrategyv4.SwapStep memory step1 = ReaperBaseStrategyv4.SwapStep({
            exType: ReaperBaseStrategyv4.ExchangeType.UniV3,
            start: opAddress,
            end: wethAddress,
            minAmountOutData: MinAmountOutData({kind: MinAmountOutKind.ChainlinkBased, absoluteOrBPSValue: 9950}),
            exchangeAddress: uniV3Router
        });

        ReaperBaseStrategyv4.SwapStep[] memory steps = new ReaperBaseStrategyv4.SwapStep[](1);
        steps[0] = step1;
        strategy.setHarvestSwapSteps(steps);
    }

    ///------ DEPLOYMENT ------\\\\

    function testVaultDeployedWith0Balance() public {
        VaultAndStratConfig storage config = configs[0];
        uint256 totalBalance = config.vault.balance();
        uint256 pricePerFullShare = config.vault.getPricePerFullShare();
        assertEq(totalBalance, 0);
        assertEq(pricePerFullShare, 10 ** IYearnVault(config.base.yearnVault).decimals());
    }

    ///------ ACCESS CONTROL ------\\\

    function testUnassignedRoleCannotPassAccessControl() public {
        vm.startPrank(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266); // random address

        VaultAndStratConfig storage config = configs[0];

        vm.expectRevert("Unauthorized access");
        config.strategy.setEmergencyExit();
    }

    function testStrategistHasRightPrivileges() public {
        vm.startPrank(strategistAddr);

        VaultAndStratConfig storage config = configs[0];

        vm.expectRevert("Unauthorized access");
        config.strategy.setEmergencyExit();
    }

    function testGuardianHasRightPrivilieges() public {
        vm.startPrank(guardianAddress);

        VaultAndStratConfig storage config = configs[0];
        config.strategy.setEmergencyExit();
    }

    function testAdminHasRightPrivileges() public {
        vm.startPrank(adminAddress);

        VaultAndStratConfig storage config = configs[0];    
        config.strategy.setEmergencyExit();
    }

    function testSuperAdminOrOwnerHasRightPrivileges() public {
        vm.startPrank(superAdminAddress);

        VaultAndStratConfig storage config = configs[0];   
        config.strategy.setEmergencyExit();
    }

    ///------ VAULT AND STRATEGY------\\\

    function testCanTakeDeposits(uint256 depositScaleFactor) public {
        depositScaleFactor = bound(depositScaleFactor, 1e8, 1e17 * 5);
        for (uint256 index = 0; index < configs.length; index++) {
            VaultAndStratConfig storage config = configs[index];

            vm.startPrank(wantHolderAddr);
            uint256 depositAmount = (config.want.balanceOf(wantHolderAddr) * depositScaleFactor) / 1 ether;
            console.log("want.balanceOf(wantHolderAddr): ", config.want.balanceOf(wantHolderAddr));
            console.log(depositAmount);
            config.vault.deposit(depositAmount);

            uint256 newVaultBalance = config.vault.balance();
            console.log(newVaultBalance);
            assertApproxEqRel(newVaultBalance, depositAmount, 0.005e18);

            config.strategy.harvest();
            _skipBlockAndTime(50);
            config.strategy.harvest();

            newVaultBalance = config.vault.balance();
            console.log(newVaultBalance);
            assertApproxEqRel(newVaultBalance, depositAmount, 0.005e18);
        }
    }

    function testVaultCanMintUserPoolShare(uint256 depositScaleFactor, uint256 aliceDepositScaleFactor) public {
        depositScaleFactor = bound(depositScaleFactor, 1e8, 1e17 * 5);
        aliceDepositScaleFactor = bound(aliceDepositScaleFactor, 1e8, 1e16 * 5);

        for (uint256 index = 0; index < configs.length; index++) {
            VaultAndStratConfig storage config = configs[index];

            address alice = makeAddr("alice");

            vm.startPrank(wantHolderAddr);
            uint256 depositAmount = (config.want.balanceOf(wantHolderAddr) * depositScaleFactor) / 1 ether;
            config.vault.deposit(depositAmount);
            uint256 aliceDepositAmount = (config.want.balanceOf(wantHolderAddr) * aliceDepositScaleFactor) / 1 ether;
            config.want.transfer(alice, aliceDepositAmount);
            vm.stopPrank();

            vm.startPrank(alice);
            config.want.approve(address(config.vault), aliceDepositAmount);
            config.vault.deposit(aliceDepositAmount);
            vm.stopPrank();

            uint256 allowedImprecision = 1e15;

            uint256 userVaultBalance = config.vault.balanceOf(wantHolderAddr);
            assertApproxEqRel(userVaultBalance, depositAmount, allowedImprecision);
            uint256 aliceVaultBalance = config.vault.balanceOf(alice);
            assertApproxEqRel(aliceVaultBalance, aliceDepositAmount, allowedImprecision);

            vm.prank(alice);
            config.vault.withdrawAll();
            uint256 aliceWantBalance = config.want.balanceOf(alice);
            assertApproxEqRel(aliceWantBalance, aliceDepositAmount, allowedImprecision);
            aliceVaultBalance = config.vault.balanceOf(alice);
            assertEq(aliceVaultBalance, 0);
        }

    }

    function testVaultAllowsWithdrawals(uint256 depositScaleFactor) public {
        depositScaleFactor = bound(depositScaleFactor, 1e10, 1e17 * 5);

        for (uint256 index = 0; index < configs.length; index++) {
            VaultAndStratConfig storage config = configs[index];

            uint256 userBalance = config.want.balanceOf(wantHolderAddr);
            console.log("userBalance: ", userBalance);
            uint256 depositAmount = (config.want.balanceOf(wantHolderAddr) * depositScaleFactor) / 1 ether;
            console.log("depositAmount: ", depositAmount);
            vm.startPrank(wantHolderAddr);
            config.vault.deposit(depositAmount);

            config.strategy.harvest();
            _skipBlockAndTime(50);
            config.strategy.harvest();

            config.vault.withdrawAll();
            uint256 userBalanceAfterWithdraw = config.want.balanceOf(wantHolderAddr);
            console.log("userBalanceAfterWithdraw: ", userBalanceAfterWithdraw);

            uint256 allowedImprecision = 1e12;
            assertApproxEqRel(userBalance, userBalanceAfterWithdraw, allowedImprecision);

        }
    }

    function testVaultAllowsSmallWithdrawal(uint256 depositScaleFactor) public {
        depositScaleFactor = bound(depositScaleFactor, 1e10, 1e12);

        for (uint256 index = 0; index < configs.length; index++) {
            VaultAndStratConfig storage config = configs[index];

            address alice = makeAddr("alice");

            vm.startPrank(wantHolderAddr);
            uint256 aliceDepositAmount = (config.want.balanceOf(wantHolderAddr) * 1000) / 10000;
            config.want.transfer(alice, aliceDepositAmount);
            uint256 userBalance = config.want.balanceOf(wantHolderAddr);
            uint256 depositAmount = (config.want.balanceOf(wantHolderAddr) * depositScaleFactor) / 1 ether;
            config.vault.deposit(depositAmount);
            vm.stopPrank();

            vm.startPrank(alice);
            config.want.approve(address(config.vault), type(uint256).max);
            config.vault.deposit(aliceDepositAmount);
            vm.stopPrank();

            vm.prank(wantHolderAddr);
            config.vault.withdrawAll();
            uint256 userBalanceAfterWithdraw = config.want.balanceOf(wantHolderAddr);

            assertEq(userBalance, userBalanceAfterWithdraw);
        }

    }

    function testVaultHandlesSmallDepositAndWithdraw(uint256 depositScaleFactor) public {
        depositScaleFactor = bound(depositScaleFactor, 1e10, 1e12);

        for (uint256 index = 0; index < configs.length; index++) {
            VaultAndStratConfig storage config = configs[index];

            uint256 userBalance = config.want.balanceOf(wantHolderAddr);
            uint256 depositAmount = (config.want.balanceOf(wantHolderAddr) * depositScaleFactor) / 1 ether;
            vm.startPrank(wantHolderAddr);
            config.vault.deposit(depositAmount);

            config.vault.withdraw(depositAmount);
            uint256 userBalanceAfterWithdraw = config.want.balanceOf(wantHolderAddr);

            assertEq(userBalance, userBalanceAfterWithdraw);
        }
    }

    function testCanHarvest(uint256 depositScaleFactor) public {
        depositScaleFactor = bound(depositScaleFactor, 1e11, 1e17);

        for (uint256 index = 0; index < configs.length; index++) {
            VaultAndStratConfig storage config = configs[index];

            uint256 timeToSkip = 3600;
            uint256 wantBalance = config.want.balanceOf(wantHolderAddr);
            uint256 depositAmount = (wantBalance * depositScaleFactor) / 1 ether;
            console.log("depositAmount: ", depositAmount);
            vm.prank(wantHolderAddr);
            config.vault.deposit(depositAmount);
            vm.startPrank(keepers[0]);
            config.strategy.harvest();

            uint256 vaultBalanceBefore = config.vault.balance();
            skip(timeToSkip);
            int256 roi = config.strategy.harvest();
            console.log("roi: ");
            console.logInt(roi);
            uint256 vaultBalanceAfter = config.vault.balance();
            console.log("vaultBalanceBefore: ", vaultBalanceBefore);
            console.log("vaultBalanceAfter: ", vaultBalanceAfter);

            assertEq(vaultBalanceAfter - vaultBalanceBefore, uint256(roi));
            vm.stopPrank();
        }
    }

    function testCanProvideYield(uint256 depositScaleFactor) public {
        depositScaleFactor = bound(depositScaleFactor, 1e11, 1e17);

        for (uint256 index = 0; index < configs.length; index++) {
            VaultAndStratConfig storage config = configs[index];

            uint256 timeToSkip = 3600;
            uint256 wantBalance = config.want.balanceOf(wantHolderAddr);
            uint256 depositAmount = (wantBalance * depositScaleFactor) / 1 ether;
            console.log("depositAmount: ", depositAmount);

            vm.prank(wantHolderAddr);
            config.vault.deposit(depositAmount);
            uint256 initialVaultBalance = config.vault.balance();

            uint256 numHarvests = 5;

            for (uint256 i; i < numHarvests; i++) {
                skip(timeToSkip);
                config.strategy.harvest();
            }

            uint256 finalVaultBalance = config.vault.balance();
            console.log("initialVaultBalance: ", initialVaultBalance);
            console.log("finalVaultBalance: ", finalVaultBalance);
            assertEq(finalVaultBalance > initialVaultBalance, true);
        }
    }

    function testStrategyGetsMoreFunds(uint256 depositScaleFactor) public {
        depositScaleFactor = bound(depositScaleFactor, 1e11, 1e17);

        for (uint256 index = 0; index < configs.length; index++) {
            VaultAndStratConfig storage config = configs[index];

            uint256 startingAllocationBPS = 9000;
            config.vault.updateStrategyAllocBPS(address(config.strategy), startingAllocationBPS);
            uint256 timeToSkip = 3600;
            uint256 wantBalance = config.want.balanceOf(wantHolderAddr);
            uint256 depositAmount = (wantBalance * depositScaleFactor) / 1 ether;
            console.log("depositAmount: ", depositAmount);

            vm.prank(wantHolderAddr);
            config.vault.deposit(depositAmount);

            config.strategy.harvest();
            skip(timeToSkip);
            uint256 vaultBalance = config.vault.balance();
            uint256 vaultWantBalance = config.want.balanceOf(address(config.vault));
            uint256 strategyBalance = config.strategy.balanceOf();
            assertEq(vaultBalance, depositAmount);
            assertApproxEqAbs(vaultWantBalance, depositAmount  / 10, 5);
            uint256 allowedImprecision = 1e13;
            assertApproxEqRel(strategyBalance, depositAmount  / 10 * 9, allowedImprecision);

            vm.prank(wantHolderAddr);
            config.vault.deposit(depositAmount);

            config.strategy.harvest();
            skip(timeToSkip);

            vaultBalance = config.vault.balance();
            vaultWantBalance = config.want.balanceOf(address(config.vault));
            strategyBalance = config.strategy.balanceOf();
            console.log("strategyBalance: ", strategyBalance);
            console.log("vaultBalance: ", vaultBalance);
            console.log("depositAmount * 2: ", depositAmount * 2);
            assertGe(vaultBalance, depositAmount * 2);
            assertGt(vaultWantBalance, depositAmount / 10);
            assertGt(strategyBalance, depositAmount / 10 * 9);
        }
    }

    function testVaultPullsFunds(uint256 depositScaleFactor) public {
        depositScaleFactor = bound(depositScaleFactor, 1e11, 1e17);

        for (uint256 index = 0; index < configs.length; index++) {
            VaultAndStratConfig storage config = configs[index];

            uint256 startingAllocationBPS = 9000;
            config.vault.updateStrategyAllocBPS(address(config.strategy), startingAllocationBPS);
            uint256 timeToSkip = 3600;
            uint256 wantBalance = config.want.balanceOf(wantHolderAddr);
            uint256 depositAmount = (wantBalance * depositScaleFactor) / 1 ether;
            console.log("depositAmount: ", depositAmount);

            vm.prank(wantHolderAddr);
            config.vault.deposit(depositAmount);

            config.strategy.harvest();
            skip(timeToSkip);

            uint256 vaultBalance = config.vault.balance();
            uint256 vaultWantBalance = config.want.balanceOf(address(config.vault));
            uint256 strategyBalance = config.strategy.balanceOf();
            assertEq(vaultBalance, depositAmount);
            assertApproxEqAbs(vaultWantBalance, depositAmount / 10, 5);
            uint256 allowedImprecision = 1e13;
            assertApproxEqRel(strategyBalance, depositAmount  / 10 * 9, allowedImprecision);

            uint256 newAllocationBPS = 7000;
            config.vault.updateStrategyAllocBPS(address(config.strategy), newAllocationBPS);
            config.strategy.harvest();

            vaultBalance = config.vault.balance();
            vaultWantBalance = config.want.balanceOf(address(config.vault));
            strategyBalance = config.strategy.balanceOf();
            if (vaultBalance <= depositAmount) {
                assertApproxEqAbs(vaultBalance, depositAmount, 5);
            }
            if (vaultWantBalance <=  depositAmount / 10 * 3) {
                assertApproxEqAbs(vaultWantBalance, depositAmount / 10 * 3, 5);
            }
            assertApproxEqRel(strategyBalance, depositAmount / 10 * 7, allowedImprecision);

            vm.prank(wantHolderAddr);
            config.vault.deposit(depositAmount);

            config.strategy.harvest();
            skip(timeToSkip);

            vaultBalance = config.vault.balance();
            vaultWantBalance = config.want.balanceOf(address(config.vault));
            strategyBalance = config.strategy.balanceOf();
            if (vaultBalance <= depositAmount * 2) {
                assertApproxEqAbs(vaultBalance, depositAmount * 2, 5);
            }
            if (vaultBalance <= depositAmount / 10 * 6) {
                assertApproxEqAbs(vaultWantBalance, depositAmount / 10 * 6, 5);
            }
            assertGt(strategyBalance, depositAmount / 10 * 14);
        }
    }

    function testEmergencyShutdown(uint256 depositScaleFactor) public {
        depositScaleFactor = bound(depositScaleFactor, 1e11, 1e17);

        for (uint256 index = 0; index < configs.length; index++) {
            VaultAndStratConfig storage config = configs[index];

            uint256 startingAllocationBPS = 9000;
            config.vault.updateStrategyAllocBPS(address(config.strategy), startingAllocationBPS);
            uint256 timeToSkip = 3600;
            uint256 wantBalance = config.want.balanceOf(wantHolderAddr);
            uint256 depositAmount = (wantBalance * depositScaleFactor) / 1 ether;
            console.log("depositAmount: ", depositAmount);

            vm.prank(wantHolderAddr);
            config.vault.deposit(depositAmount);

            config.strategy.harvest();
            skip(timeToSkip);

            uint256 vaultBalance = config.vault.balance();
            uint256 vaultWantBalance = config.want.balanceOf(address(config.vault));
            uint256 strategyBalance = config.strategy.balanceOf();
            assertEq(vaultBalance, depositAmount);
            assertApproxEqAbs(vaultWantBalance, depositAmount / 10, 5);
            uint256 allowedImprecision = 1e13;
            assertApproxEqRel(strategyBalance, depositAmount  / 10 * 9, allowedImprecision);

            config.vault.setEmergencyShutdown(true);
            config.strategy.harvest();

            vaultBalance = config.vault.balance();
            vaultWantBalance = config.want.balanceOf(address(config.vault));
            strategyBalance = config.strategy.balanceOf();
            console.log("vaultBalance: ", vaultBalance);
            console.log("depositAmount: ", depositAmount);
            console.log("vaultWantBalance: ", vaultWantBalance);
            console.log("strategyBalance: ", strategyBalance);
            assertGe(vaultBalance, depositAmount);
            assertGe(vaultWantBalance, depositAmount);
            uint256 maxRemaining = depositAmount * 1e12 / 1 ether;
            console.log("maxRemaining: ", maxRemaining);
            if (maxRemaining <= 5) {
                maxRemaining = 5;
            }
            assertApproxEqAbs(strategyBalance, 0, maxRemaining);
        }

    }

    function testDisablingStakingWillUnstake() public {
        for (uint256 index = 0; index < configs.length; index++) {
            VaultAndStratConfig storage config = configs[index];

            uint256 depositAmount = _toWant(5, address(config.want));
            vm.prank(wantHolderAddr);
            config.vault.deposit(depositAmount);

            config.strategy.harvest();
            uint256 stakingBalance1 = IStakingRewards(config.base.stakingRewards).balanceOf(address(config.strategy));
            config.strategy.setShouldStake(false);
            uint256 stakingBalance2 = IStakingRewards(config.base.stakingRewards).balanceOf(address(config.strategy));

            uint256 stakingBalance3 = IStakingRewards(config.base.stakingRewards).balanceOf(address(config.strategy));
            config.strategy.setShouldStake(true);
            uint256 stakingBalance4 = IStakingRewards(config.base.stakingRewards).balanceOf(address(config.strategy));

            uint256 pricePerShare = IYearnVault(config.base.yearnVault).pricePerShare();

            uint256 expectedShares = depositAmount * 10 ** IYearnVault(config.base.yearnVault).decimals() / pricePerShare;

            console.log("stakingBalance1: ", stakingBalance1);
            console.log("stakingBalance2: ", stakingBalance2);
            console.log("stakingBalance3: ", stakingBalance3);
            console.log("stakingBalance4: ", stakingBalance4);

            console.log("pricePerShare: ", pricePerShare);

            console.log("expectedShares: ", expectedShares);

            assertApproxEqAbs(stakingBalance1, expectedShares, 5);
            assertEq(stakingBalance2, 0);
            assertEq(stakingBalance3, 0);
            assertEq(stakingBalance1, stakingBalance4);
        }

    }

    function _toWant(uint256 amount, address want) internal returns (uint256) {
        return amount * (10 ** ERC20(want).decimals());
    }

    function _skipBlockAndTime(uint256 _amount) private {
        // console.log("_skipBlockAndTime");

        // console.log("block.timestamp: ", block.timestamp);
        skip(_amount * 2);
        // console.log("block.timestamp: ", block.timestamp);

        // console.log("block.number: ", block.number);
        vm.roll(block.number + _amount);
        // console.log("block.number: ", block.number);
    }
}
