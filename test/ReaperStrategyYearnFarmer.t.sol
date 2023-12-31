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
    address public yearnVault = usdcYearnVault;
    address public wethStakingRewards = 0xE35Fec3895Dcecc7d2a91e8ae4fF3c0d43ebfFE0;
    address public usdcStakingRewards = 0xB2c04C55979B6CA7EB10e666933DE5ED84E6876b;
    address public stakingRewards = usdcStakingRewards;

    address public superAdminAddress = 0x9BC776dBb134Ef9D7014dB1823Cd755Ac5015203;
    address public adminAddress = 0xeb9C9b785aA7818B2EBC8f9842926c4B9f707e4B;
    address public guardianAddress = 0xb0C9D5851deF8A2Aac4A23031CA2610f8C3483F9;

    address public wethAddress = 0x4200000000000000000000000000000000000006;
    address public wbtcAddress = 0x68f180fcCe6836688e9084f035309E29Bf0A2095;
    address public opAddress = 0x4200000000000000000000000000000000000042;
    address public usdcAddress = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
    address public wantAddress = usdcAddress;

    address public strategistAddr = 0x1A20D7A31e5B3Bc5f02c8A146EF6f394502a10c4;
    address public wantHolderAddr = strategistAddr;

    uint256 BPS_UNIT = 10_000;

    address[] keepers = [
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

    // Initialized during set up in initial tests
    ReaperVaultV2 public vault;
    string public vaultName = "Yearn farmer Vault";
    string public vaultSymbol = "rf-yv-WETH";
    uint256 public vaultTvlCap = type(uint256).max;

    ReaperStrategyYearnFarmer public implementation;
    ERC1967Proxy public proxy;
    ReaperStrategyYearnFarmer public wrappedProxy;

    ISwapper public swapper;

    ERC20 public want = ERC20(wantAddress);

    function setUp() public {
        // Forking
        string memory rpc = vm.envString("RPC");
        optimismFork = vm.createSelectFork(rpc, 107994026);
        assertEq(vm.activeFork(), optimismFork);

        // // Deploying stuff
        ReaperSwapper swapperImpl = new ReaperSwapper();
        ERC1967Proxy swapperProxy = new ERC1967Proxy(address(swapperImpl), "");
        ReaperSwapper wrappedSwapperProxy = ReaperSwapper(address(swapperProxy));
        wrappedSwapperProxy.initialize(strategists, guardianAddress, superAdminAddress);
        swapper = ISwapper(address(swapperProxy));

        vault =
        new ReaperVaultV2(wantAddress, vaultName, vaultSymbol, vaultTvlCap, treasuryAddress, strategists, multisigRoles);
        implementation = new ReaperStrategyYearnFarmer();
        proxy = new ERC1967Proxy(address(implementation), "");
        wrappedProxy = ReaperStrategyYearnFarmer(address(proxy));

        // address _vault,
        // address _swapper,
        // address[] memory _strategists,
        // address[] memory _multisigRoles,
        // address[] memory _keepers,
        // address _yearnVault

        bool shouldStake = true;
        wrappedProxy.initialize(
            address(vault),
            address(swapper),
            strategists,
            multisigRoles,
            keepers,
            yearnVault,
            stakingRewards,
            shouldStake
        );

        uint256 feeBPS = 1000;
        uint256 allocation = 10_000;
        vault.addStrategy(address(wrappedProxy), feeBPS, allocation);

        vm.prank(wantHolderAddr);
        want.approve(address(vault), type(uint256).max);
        deal({token: address(want), to: wantHolderAddr, give: _toWant(10_000_000)});

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

        ReaperBaseStrategyv4.SwapStep memory step1 = ReaperBaseStrategyv4.SwapStep({
            exType: ReaperBaseStrategyv4.ExchangeType.UniV3,
            start: opAddress,
            end: wethAddress,
            minAmountOutData: MinAmountOutData({kind: MinAmountOutKind.ChainlinkBased, absoluteOrBPSValue: 9950}),
            exchangeAddress: uniV3Router
        });

        ReaperBaseStrategyv4.SwapStep[] memory steps = new ReaperBaseStrategyv4.SwapStep[](1);
        steps[0] = step1;
        wrappedProxy.setHarvestSwapSteps(steps);
    }

    ///------ DEPLOYMENT ------\\\\

    function testVaultDeployedWith0Balance() public {
        uint256 totalBalance = vault.balance();
        uint256 pricePerFullShare = vault.getPricePerFullShare();
        assertEq(totalBalance, 0);
        assertEq(pricePerFullShare, 10 ** IYearnVault(yearnVault).decimals());
    }

    ///------ ACCESS CONTROL ------\\\

    function testUnassignedRoleCannotPassAccessControl() public {
        vm.startPrank(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266); // random address

        vm.expectRevert("Unauthorized access");
        wrappedProxy.setEmergencyExit();
    }

    function testStrategistHasRightPrivileges() public {
        vm.startPrank(strategistAddr);

        vm.expectRevert("Unauthorized access");
        wrappedProxy.setEmergencyExit();
    }

    function testGuardianHasRightPrivilieges() public {
        vm.startPrank(guardianAddress);

        wrappedProxy.setEmergencyExit();
    }

    function testAdminHasRightPrivileges() public {
        vm.startPrank(adminAddress);

        wrappedProxy.setEmergencyExit();
    }

    function testSuperAdminOrOwnerHasRightPrivileges() public {
        vm.startPrank(superAdminAddress);

        wrappedProxy.setEmergencyExit();
    }

    ///------ VAULT AND STRATEGY------\\\

    function testCanTakeDeposits(uint256 depositScaleFactor) public {
        depositScaleFactor = bound(depositScaleFactor, 1e8, 1e17 * 5);
        vm.startPrank(wantHolderAddr);
        uint256 depositAmount = (want.balanceOf(wantHolderAddr) * depositScaleFactor) / 1 ether;
        console.log("want.balanceOf(wantHolderAddr): ", want.balanceOf(wantHolderAddr));
        console.log(depositAmount);
        vault.deposit(depositAmount);

        uint256 newVaultBalance = vault.balance();
        console.log(newVaultBalance);
        assertApproxEqRel(newVaultBalance, depositAmount, 0.005e18);

        wrappedProxy.harvest();
        _skipBlockAndTime(50);
        wrappedProxy.harvest();

        newVaultBalance = vault.balance();
        console.log(newVaultBalance);
        assertApproxEqRel(newVaultBalance, depositAmount, 0.005e18);
    }

    function testVaultCanMintUserPoolShare(uint256 depositScaleFactor, uint256 aliceDepositScaleFactor) public {
        depositScaleFactor = bound(depositScaleFactor, 1e8, 1e17 * 5);
        aliceDepositScaleFactor = bound(aliceDepositScaleFactor, 1e8, 1e16 * 5);
        address alice = makeAddr("alice");

        vm.startPrank(wantHolderAddr);
        uint256 depositAmount = (want.balanceOf(wantHolderAddr) * depositScaleFactor) / 1 ether;
        vault.deposit(depositAmount);
        uint256 aliceDepositAmount = (want.balanceOf(wantHolderAddr) * aliceDepositScaleFactor) / 1 ether;
        want.transfer(alice, aliceDepositAmount);
        vm.stopPrank();

        vm.startPrank(alice);
        want.approve(address(vault), aliceDepositAmount);
        vault.deposit(aliceDepositAmount);
        vm.stopPrank();

        uint256 allowedImprecision = 1e15;

        uint256 userVaultBalance = vault.balanceOf(wantHolderAddr);
        assertApproxEqRel(userVaultBalance, depositAmount, allowedImprecision);
        uint256 aliceVaultBalance = vault.balanceOf(alice);
        assertApproxEqRel(aliceVaultBalance, aliceDepositAmount, allowedImprecision);

        vm.prank(alice);
        vault.withdrawAll();
        uint256 aliceWantBalance = want.balanceOf(alice);
        assertApproxEqRel(aliceWantBalance, aliceDepositAmount, allowedImprecision);
        aliceVaultBalance = vault.balanceOf(alice);
        assertEq(aliceVaultBalance, 0);
    }

    function testVaultAllowsWithdrawals(uint256 depositScaleFactor) public {
        depositScaleFactor = bound(depositScaleFactor, 1e10, 1e17 * 5);
        uint256 userBalance = want.balanceOf(wantHolderAddr);
        console.log("userBalance: ", userBalance);
        uint256 depositAmount = (want.balanceOf(wantHolderAddr) * depositScaleFactor) / 1 ether;
        console.log("depositAmount: ", depositAmount);
        vm.startPrank(wantHolderAddr);
        vault.deposit(depositAmount);

        wrappedProxy.harvest();
        _skipBlockAndTime(50);
        wrappedProxy.harvest();

        vault.withdrawAll();
        uint256 userBalanceAfterWithdraw = want.balanceOf(wantHolderAddr);
        console.log("userBalanceAfterWithdraw: ", userBalanceAfterWithdraw);

        uint256 allowedImprecision = 1e12;
        assertApproxEqRel(userBalance, userBalanceAfterWithdraw, allowedImprecision);
    }

    function testVaultAllowsSmallWithdrawal(uint256 depositScaleFactor) public {
        depositScaleFactor = bound(depositScaleFactor, 1e10, 1e12);
        address alice = makeAddr("alice");

        vm.startPrank(wantHolderAddr);
        uint256 aliceDepositAmount = (want.balanceOf(wantHolderAddr) * 1000) / 10000;
        want.transfer(alice, aliceDepositAmount);
        uint256 userBalance = want.balanceOf(wantHolderAddr);
        uint256 depositAmount = (want.balanceOf(wantHolderAddr) * depositScaleFactor) / 1 ether;
        vault.deposit(depositAmount);
        vm.stopPrank();

        vm.startPrank(alice);
        want.approve(address(vault), type(uint256).max);
        vault.deposit(aliceDepositAmount);
        vm.stopPrank();

        vm.prank(wantHolderAddr);
        vault.withdrawAll();
        uint256 userBalanceAfterWithdraw = want.balanceOf(wantHolderAddr);

        assertEq(userBalance, userBalanceAfterWithdraw);
    }

    function testVaultHandlesSmallDepositAndWithdraw(uint256 depositScaleFactor) public {
        depositScaleFactor = bound(depositScaleFactor, 1e10, 1e12);
        uint256 userBalance = want.balanceOf(wantHolderAddr);
        uint256 depositAmount = (want.balanceOf(wantHolderAddr) * depositScaleFactor) / 1 ether;
        vm.startPrank(wantHolderAddr);
        vault.deposit(depositAmount);

        vault.withdraw(depositAmount);
        uint256 userBalanceAfterWithdraw = want.balanceOf(wantHolderAddr);

        assertEq(userBalance, userBalanceAfterWithdraw);
    }

    function testCanHarvest(uint256 depositScaleFactor) public {
        depositScaleFactor = bound(depositScaleFactor, 1e11, 1e17);
        uint256 timeToSkip = 3600;
        uint256 wantBalance = want.balanceOf(wantHolderAddr);
        uint256 depositAmount = (wantBalance * depositScaleFactor) / 1 ether;
        console.log("depositAmount: ", depositAmount);
        vm.prank(wantHolderAddr);
        vault.deposit(depositAmount);
        vm.startPrank(keepers[0]);
        wrappedProxy.harvest();

        uint256 vaultBalanceBefore = vault.balance();
        skip(timeToSkip);
        int256 roi = wrappedProxy.harvest();
        console.log("roi: ");
        console.logInt(roi);
        uint256 vaultBalanceAfter = vault.balance();
        console.log("vaultBalanceBefore: ", vaultBalanceBefore);
        console.log("vaultBalanceAfter: ", vaultBalanceAfter);

        assertEq(vaultBalanceAfter - vaultBalanceBefore, uint256(roi));
    }

    function testCanProvideYield(uint256 depositScaleFactor) public {
        depositScaleFactor = bound(depositScaleFactor, 1e11, 1e17);
        uint256 timeToSkip = 3600;
        uint256 wantBalance = want.balanceOf(wantHolderAddr);
        uint256 depositAmount = (wantBalance * depositScaleFactor) / 1 ether;
        console.log("depositAmount: ", depositAmount);

        vm.prank(wantHolderAddr);
        vault.deposit(depositAmount);
        uint256 initialVaultBalance = vault.balance();

        uint256 numHarvests = 5;

        for (uint256 i; i < numHarvests; i++) {
            skip(timeToSkip);
            wrappedProxy.harvest();
        }

        uint256 finalVaultBalance = vault.balance();
        console.log("initialVaultBalance: ", initialVaultBalance);
        console.log("finalVaultBalance: ", finalVaultBalance);
        assertEq(finalVaultBalance > initialVaultBalance, true);
    }

    function testStrategyGetsMoreFunds(uint256 depositScaleFactor) public {
        depositScaleFactor = bound(depositScaleFactor, 1e11, 1e17);
        uint256 startingAllocationBPS = 9000;
        vault.updateStrategyAllocBPS(address(wrappedProxy), startingAllocationBPS);
        uint256 timeToSkip = 3600;
        uint256 wantBalance = want.balanceOf(wantHolderAddr);
        uint256 depositAmount = (wantBalance * depositScaleFactor) / 1 ether;
        console.log("depositAmount: ", depositAmount);

        vm.prank(wantHolderAddr);
        vault.deposit(depositAmount);

        wrappedProxy.harvest();
        skip(timeToSkip);
        uint256 vaultBalance = vault.balance();
        uint256 vaultWantBalance = want.balanceOf(address(vault));
        uint256 strategyBalance = wrappedProxy.balanceOf();
        assertEq(vaultBalance, depositAmount);
        assertApproxEqAbs(vaultWantBalance, depositAmount  / 10, 5);
        uint256 allowedImprecision = 1e13;
        assertApproxEqRel(strategyBalance, depositAmount  / 10 * 9, allowedImprecision);

        vm.prank(wantHolderAddr);
        vault.deposit(depositAmount);

        wrappedProxy.harvest();
        skip(timeToSkip);

        vaultBalance = vault.balance();
        vaultWantBalance = want.balanceOf(address(vault));
        strategyBalance = wrappedProxy.balanceOf();
        console.log("strategyBalance: ", strategyBalance);
        console.log("vaultBalance: ", vaultBalance);
        console.log("depositAmount * 2: ", depositAmount * 2);
        assertGe(vaultBalance, depositAmount * 2);
        assertGt(vaultWantBalance, depositAmount / 10);
        assertGt(strategyBalance, depositAmount / 10 * 9);
    }

    function testVaultPullsFunds(uint256 depositScaleFactor) public {
        depositScaleFactor = bound(depositScaleFactor, 1e11, 1e17);
        uint256 startingAllocationBPS = 9000;
        vault.updateStrategyAllocBPS(address(wrappedProxy), startingAllocationBPS);
        uint256 timeToSkip = 3600;
        uint256 wantBalance = want.balanceOf(wantHolderAddr);
        uint256 depositAmount = (wantBalance * depositScaleFactor) / 1 ether;
        console.log("depositAmount: ", depositAmount);

        vm.prank(wantHolderAddr);
        vault.deposit(depositAmount);

        wrappedProxy.harvest();
        skip(timeToSkip);

        uint256 vaultBalance = vault.balance();
        uint256 vaultWantBalance = want.balanceOf(address(vault));
        uint256 strategyBalance = wrappedProxy.balanceOf();
        assertEq(vaultBalance, depositAmount);
        assertApproxEqAbs(vaultWantBalance, depositAmount / 10, 5);
        uint256 allowedImprecision = 1e13;
        assertApproxEqRel(strategyBalance, depositAmount  / 10 * 9, allowedImprecision);

        uint256 newAllocationBPS = 7000;
        vault.updateStrategyAllocBPS(address(wrappedProxy), newAllocationBPS);
        wrappedProxy.harvest();

        vaultBalance = vault.balance();
        vaultWantBalance = want.balanceOf(address(vault));
        strategyBalance = wrappedProxy.balanceOf();
        if (vaultBalance <= depositAmount) {
            assertApproxEqAbs(vaultBalance, depositAmount, 5);
        }
        if (vaultWantBalance <=  depositAmount / 10 * 3) {
            assertApproxEqAbs(vaultWantBalance, depositAmount / 10 * 3, 5);
        }
        assertApproxEqRel(strategyBalance, depositAmount / 10 * 7, allowedImprecision);

        vm.prank(wantHolderAddr);
        vault.deposit(depositAmount);

        wrappedProxy.harvest();
        skip(timeToSkip);

        vaultBalance = vault.balance();
        vaultWantBalance = want.balanceOf(address(vault));
        strategyBalance = wrappedProxy.balanceOf();
        if (vaultBalance <= depositAmount * 2) {
            assertApproxEqAbs(vaultBalance, depositAmount * 2, 5);
        }
        if (vaultBalance <= depositAmount / 10 * 6) {
            assertApproxEqAbs(vaultWantBalance, depositAmount / 10 * 6, 5);
        }
        assertGt(strategyBalance, depositAmount / 10 * 14);
    }

    function testEmergencyShutdown(uint256 depositScaleFactor) public {
        depositScaleFactor = bound(depositScaleFactor, 1e11, 1e17);
        uint256 startingAllocationBPS = 9000;
        vault.updateStrategyAllocBPS(address(wrappedProxy), startingAllocationBPS);
        uint256 timeToSkip = 3600;
        uint256 wantBalance = want.balanceOf(wantHolderAddr);
        uint256 depositAmount = (wantBalance * depositScaleFactor) / 1 ether;
        console.log("depositAmount: ", depositAmount);

        vm.prank(wantHolderAddr);
        vault.deposit(depositAmount);

        wrappedProxy.harvest();
        skip(timeToSkip);

        uint256 vaultBalance = vault.balance();
        uint256 vaultWantBalance = want.balanceOf(address(vault));
        uint256 strategyBalance = wrappedProxy.balanceOf();
        assertEq(vaultBalance, depositAmount);
        assertApproxEqAbs(vaultWantBalance, depositAmount / 10, 5);
        uint256 allowedImprecision = 1e13;
        assertApproxEqRel(strategyBalance, depositAmount  / 10 * 9, allowedImprecision);

        vault.setEmergencyShutdown(true);
        wrappedProxy.harvest();

        vaultBalance = vault.balance();
        vaultWantBalance = want.balanceOf(address(vault));
        strategyBalance = wrappedProxy.balanceOf();
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

    function testDisablingStakingWillUnstake() public {
        uint256 depositAmount = _toWant(5);
        vm.prank(wantHolderAddr);
        vault.deposit(depositAmount);

        wrappedProxy.harvest();
        uint256 stakingBalance1 = IStakingRewards(stakingRewards).balanceOf(address(wrappedProxy));
        wrappedProxy.setShouldStake(false);
        uint256 stakingBalance2 = IStakingRewards(stakingRewards).balanceOf(address(wrappedProxy));

        uint256 stakingBalance3 = IStakingRewards(stakingRewards).balanceOf(address(wrappedProxy));
        wrappedProxy.setShouldStake(true);
        uint256 stakingBalance4 = IStakingRewards(stakingRewards).balanceOf(address(wrappedProxy));

        uint256 pricePerShare = IYearnVault(yearnVault).pricePerShare();

        uint256 expectedShares = depositAmount * 10 ** IYearnVault(yearnVault).decimals() / pricePerShare;

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

    function _toWant(uint256 amount) internal returns (uint256) {
        return amount * (10 ** want.decimals());
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
