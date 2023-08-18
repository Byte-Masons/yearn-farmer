// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "src/ReaperStrategyYearnFarmer.sol";
import "vault-v2/ReaperSwapper.sol";
import "vault-v2/ReaperVaultV2.sol";
import "vault-v2/ReaperBaseStrategyv4.sol";
import "vault-v2/interfaces/ISwapper.sol";
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

    address public superAdminAddress = 0x9BC776dBb134Ef9D7014dB1823Cd755Ac5015203;
    address public adminAddress = 0xeb9C9b785aA7818B2EBC8f9842926c4B9f707e4B;
    address public guardianAddress = 0xb0C9D5851deF8A2Aac4A23031CA2610f8C3483F9;

    address public wantAddress = 0xc5b001DC33727F8F26880B184090D3E252470D45;
    address public wethAddress = 0x4200000000000000000000000000000000000006;
    address public wbtcAddress = 0x68f180fcCe6836688e9084f035309E29Bf0A2095;
    address public opAddress = 0x4200000000000000000000000000000000000042;

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
    // vault, strategy, want, wftm, owner, wantHolder, strategist, guardian, admin, superAdmin, unassignedRole
    ReaperVaultV2 public vault;
    string public vaultName = "Yearn farmer Vault";
    string public vaultSymbol = "rf-yv-WETH";
    uint256 public vaultTvlCap = type(uint256).max;

    ReaperStrategyYearnFarmer public implementation;
    ERC1967Proxy public proxy;
    ReaperStrategyYearnFarmer public wrappedProxy;

    ISwapper public swapper;

    ERC20 public want = ERC20(wantAddress);
    ERC20 public wftm = ERC20(wethAddress);

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

        wrappedProxy.initialize(
            address(vault),
            address(swapper),
            wantAddress,
            strategists,
            multisigRoles,
            keepers
        );

        uint256 feeBPS = 1000;
        uint256 allocation = 10_000;
        vault.addStrategy(address(wrappedProxy), feeBPS, allocation);

        vm.prank(wantHolderAddr);
        want.approve(address(vault), type(uint256).max);
        deal({token: address(want), to: wantHolderAddr, give: _toWant(100)});

        // ReaperBaseStrategyv4.SwapStep memory step1 = ReaperBaseStrategyv4.SwapStep({
        //     exType: ReaperBaseStrategyv4.ExchangeType.UniV3,
        //     start: opAddress,
        //     end: usdcAddress,
        //     minAmountOutData: MinAmountOutData({kind: MinAmountOutKind.ChainlinkBased, absoluteOrBPSValue: 9950}),
        //     exchangeAddress: uniV3Router
        // });
        
        // ReaperBaseStrategyv4.SwapStep[] memory steps = new ReaperBaseStrategyv4.SwapStep[](1);
        // steps[0] = step1;
        // wrappedProxy.setHarvestSwapSteps(steps);
    }

    ///------ DEPLOYMENT ------\\\\

    function testVaultDeployedWith0Balance() public {
        uint256 totalBalance = vault.balance();
        uint256 pricePerFullShare = vault.getPricePerFullShare();
        assertEq(totalBalance, 0);
        assertEq(pricePerFullShare, 1e18);
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

    // function testCanTakeDeposits() public {
    //     vm.startPrank(wantHolderAddr);
    //     uint256 depositAmount = (want.balanceOf(wantHolderAddr) * 2000) / 10000;
    //     console.log("want.balanceOf(wantHolderAddr): ", want.balanceOf(wantHolderAddr));
    //     console.log(depositAmount);
    //     vault.deposit(depositAmount);

    //     uint256 newVaultBalance = vault.balance();
    //     console.log(newVaultBalance);
    //     assertApproxEqRel(newVaultBalance, depositAmount, 0.005e18);
    // }

    // function testVaultCanMintUserPoolShare() public {
    //     address alice = makeAddr("alice");

    //     vm.startPrank(wantHolderAddr);
    //     uint256 depositAmount = (want.balanceOf(wantHolderAddr) * 2000) / 10000;
    //     vault.deposit(depositAmount);
    //     uint256 aliceDepositAmount = (want.balanceOf(wantHolderAddr) * 5000) / 10000;
    //     want.transfer(alice, aliceDepositAmount);
    //     vm.stopPrank();

    //     vm.startPrank(alice);
    //     want.approve(address(vault), aliceDepositAmount);
    //     vault.deposit(aliceDepositAmount);
    //     vm.stopPrank();

    //     uint256 allowedImprecision = 1e15;

    //     uint256 userVaultBalance = vault.balanceOf(wantHolderAddr);
    //     assertApproxEqRel(userVaultBalance, depositAmount, allowedImprecision);
    //     uint256 aliceVaultBalance = vault.balanceOf(alice);
    //     assertApproxEqRel(aliceVaultBalance, aliceDepositAmount, allowedImprecision);

    //     vm.prank(alice);
    //     vault.withdrawAll();
    //     uint256 aliceWantBalance = want.balanceOf(alice);
    //     assertApproxEqRel(aliceWantBalance, aliceDepositAmount, allowedImprecision);
    //     aliceVaultBalance = vault.balanceOf(alice);
    //     assertEq(aliceVaultBalance, 0);
    // }

    // function testVaultAllowsWithdrawals() public {
    //     uint256 userBalance = want.balanceOf(wantHolderAddr);
    //     uint256 depositAmount = (want.balanceOf(wantHolderAddr) * 5000) / 10000;
    //     vm.startPrank(wantHolderAddr);
    //     vault.deposit(depositAmount);
    //     vault.withdrawAll();
    //     uint256 userBalanceAfterWithdraw = want.balanceOf(wantHolderAddr);

    //     assertEq(userBalance, userBalanceAfterWithdraw);
    // }

    // function testVaultAllowsSmallWithdrawal() public {
    //     address alice = makeAddr("alice");

    //     vm.startPrank(wantHolderAddr);
    //     uint256 aliceDepositAmount = (want.balanceOf(wantHolderAddr) * 1000) / 10000;
    //     want.transfer(alice, aliceDepositAmount);
    //     uint256 userBalance = want.balanceOf(wantHolderAddr);
    //     uint256 depositAmount = (want.balanceOf(wantHolderAddr) * 100) / 10000;
    //     vault.deposit(depositAmount);
    //     vm.stopPrank();

    //     vm.startPrank(alice);
    //     want.approve(address(vault), type(uint256).max);
    //     vault.deposit(aliceDepositAmount);
    //     vm.stopPrank();

    //     vm.prank(wantHolderAddr);
    //     vault.withdrawAll();
    //     uint256 userBalanceAfterWithdraw = want.balanceOf(wantHolderAddr);

    //     assertEq(userBalance, userBalanceAfterWithdraw);
    // }

    // function testVaultHandlesSmallDepositAndWithdraw() public {
    //     uint256 userBalance = want.balanceOf(wantHolderAddr);
    //     uint256 depositAmount = (want.balanceOf(wantHolderAddr) * 10) / 10000;
    //     vm.startPrank(wantHolderAddr);
    //     vault.deposit(depositAmount);

    //     vault.withdraw(depositAmount);
    //     uint256 userBalanceAfterWithdraw = want.balanceOf(wantHolderAddr);

    //     assertEq(userBalance, userBalanceAfterWithdraw);
    // }

    // function testCanHarvest() public {
    //     uint256 timeToSkip = 3600;
    //     uint256 wantBalance = want.balanceOf(wantHolderAddr);
    //     vm.prank(wantHolderAddr);
    //     vault.deposit(wantBalance);
    //     vm.startPrank(keepers[0]);
    //     wrappedProxy.harvest();

    //     uint256 vaultBalanceBefore = vault.balance();
    //     skip(timeToSkip);
    //     int256 roi = wrappedProxy.harvest();
    //     console.log("roi: ");
    //     console.logInt(roi);
    //     uint256 vaultBalanceAfter = vault.balance();
    //     console.log("vaultBalanceBefore: ", vaultBalanceBefore);
    //     console.log("vaultBalanceAfter: ", vaultBalanceAfter);

    //     assertEq(vaultBalanceAfter - vaultBalanceBefore, uint256(roi));
    // }

    // function testCanProvideYield() public {
    //     uint256 timeToSkip = 3600;
    //     uint256 depositAmount = (want.balanceOf(wantHolderAddr) * 1000) / 10000;

    //     vm.prank(wantHolderAddr);
    //     vault.deposit(depositAmount);
    //     uint256 initialVaultBalance = vault.balance();

    //     uint256 numHarvests = 5;

    //     for (uint256 i; i < numHarvests; i++) {
    //         skip(timeToSkip);
    //         wrappedProxy.harvest();
    //     }

    //     uint256 finalVaultBalance = vault.balance();
    //     console.log("initialVaultBalance: ", initialVaultBalance);
    //     console.log("finalVaultBalance: ", finalVaultBalance);
    //     assertEq(finalVaultBalance > initialVaultBalance, true);
    // }

    // function testStrategyGetsMoreFunds() public {
    //     uint256 startingAllocationBPS = 9000;
    //     vault.updateStrategyAllocBPS(address(wrappedProxy), startingAllocationBPS);
    //     uint256 timeToSkip = 3600;
    //     uint256 depositAmount = 500 ether;

    //     vm.prank(wantHolderAddr);
    //     vault.deposit(depositAmount);

    //     wrappedProxy.harvest();
    //     skip(timeToSkip);
    //     uint256 vaultBalance = vault.balance();
    //     uint256 vaultWantBalance = want.balanceOf(address(vault));
    //     uint256 strategyBalance = wrappedProxy.balanceOf();
    //     assertEq(vaultBalance, depositAmount);
    //     assertEq(vaultWantBalance, 50 ether);
    //     assertEq(strategyBalance, 450 ether);

    //     vm.prank(wantHolderAddr);
    //     vault.deposit(depositAmount);

    //     wrappedProxy.harvest();
    //     skip(timeToSkip);

    //     vaultBalance = vault.balance();
    //     vaultWantBalance = want.balanceOf(address(vault));
    //     strategyBalance = wrappedProxy.balanceOf();
    //     console.log("strategyBalance: ", strategyBalance);
    //     assertGt(vaultBalance, depositAmount * 2);
    //     assertGt(vaultWantBalance, 100 ether);
    //     assertEq(strategyBalance, 900 ether);
    // }

    // function testVaultPullsFunds() public {
    //     uint256 startingAllocationBPS = 9000;
    //     vault.updateStrategyAllocBPS(address(wrappedProxy), startingAllocationBPS);
    //     uint256 timeToSkip = 3600;
    //     uint256 depositAmount = 100 ether;

    //     vm.prank(wantHolderAddr);
    //     vault.deposit(depositAmount);

    //     wrappedProxy.harvest();
    //     skip(timeToSkip);

    //     uint256 vaultBalance = vault.balance();
    //     uint256 vaultWantBalance = want.balanceOf(address(vault));
    //     uint256 strategyBalance = wrappedProxy.balanceOf();
    //     assertEq(vaultBalance, depositAmount);
    //     assertEq(vaultWantBalance, 10 ether);
    //     assertEq(strategyBalance, 90 ether);

    //     uint256 newAllocationBPS = 7000;
    //     vault.updateStrategyAllocBPS(address(wrappedProxy), newAllocationBPS);
    //     wrappedProxy.harvest();

    //     vaultBalance = vault.balance();
    //     vaultWantBalance = want.balanceOf(address(vault));
    //     strategyBalance = wrappedProxy.balanceOf();
    //     assertGt(vaultBalance, depositAmount);
    //     assertGt(vaultWantBalance, 30 ether);
    //     assertEq(strategyBalance, 70 ether);

    //     vm.prank(wantHolderAddr);
    //     vault.deposit(depositAmount);

    //     wrappedProxy.harvest();
    //     skip(timeToSkip);

    //     vaultBalance = vault.balance();
    //     vaultWantBalance = want.balanceOf(address(vault));
    //     strategyBalance = wrappedProxy.balanceOf();
    //     assertGt(vaultBalance, depositAmount * 2);
    //     assertGt(vaultWantBalance, 60 ether);
    //     assertGt(strategyBalance, 140 ether);
    // }

    // function testEmergencyShutdown() public {
    //     uint256 startingAllocationBPS = 9000;
    //     vault.updateStrategyAllocBPS(address(wrappedProxy), startingAllocationBPS);
    //     uint256 timeToSkip = 3600;
    //     uint256 depositAmount = 1000 ether;

    //     vm.prank(wantHolderAddr);
    //     vault.deposit(depositAmount);

    //     wrappedProxy.harvest();
    //     skip(timeToSkip);

    //     uint256 vaultBalance = vault.balance();
    //     uint256 vaultWantBalance = want.balanceOf(address(vault));
    //     uint256 strategyBalance = wrappedProxy.balanceOf();
    //     assertEq(vaultBalance, depositAmount);
    //     assertEq(vaultWantBalance, 100 ether);
    //     assertEq(strategyBalance, 900 ether);

    //     vault.setEmergencyShutdown(true);
    //     wrappedProxy.harvest();

    //     vaultBalance = vault.balance();
    //     vaultWantBalance = want.balanceOf(address(vault));
    //     strategyBalance = wrappedProxy.balanceOf();
    //     console.log("vaultBalance: ", vaultBalance);
    //     console.log("depositAmount: ", depositAmount);
    //     console.log("vaultWantBalance: ", vaultWantBalance);
    //     console.log("strategyBalance: ", strategyBalance);
    //     assertGt(vaultBalance, depositAmount);
    //     assertGt(vaultWantBalance, depositAmount);
    //     assertEq(strategyBalance, 0);
    // }

    // function testSharePriceChanges() public {
    //     // uint256 sharePrice1 = vault.getPricePerFullShare();
    //     // uint256 timeToSkip = 36000;
    //     // uint256 wantBalance = want.balanceOf(wantHolderAddr);
    //     // vm.prank(wantHolderAddr);
    //     // vault.deposit(wantBalance);
    //     // uint256 sharePrice2 = vault.getPricePerFullShare();
    //     // vm.prank(keepers[0]);
    //     // wrappedProxy.harvest();
    //     // skip(timeToSkip);
    //     // uint256 sharePrice3 = vault.getPricePerFullShare();

    //     // address wethAggregator = IPriceFeed(priceFeedAddress).priceAggregator(wethAddress);
    //     // console.log("wethAggregator: ", wethAggregator);

    //     // MockAggregator mockChainlink = new MockAggregator();
    //     // mockChainlink.setPrevRoundId(2);
    //     // mockChainlink.setLatestRoundId(3);
    //     // mockChainlink.setPrice(1500 * 10 ** 8);
    //     // mockChainlink.setPrevPrice(1500 * 10 ** 8);
    //     // mockChainlink.setUpdateTime(block.timestamp);

    //     // MockAggregator mockChainlink2 = new MockAggregator();
    //     // mockChainlink2.setPrevRoundId(2);
    //     // mockChainlink2.setLatestRoundId(3);
    //     // mockChainlink2.setPrice(25_000 * 10 ** 8);
    //     // mockChainlink2.setPrevPrice(25_000 * 10 ** 8);
    //     // mockChainlink2.setUpdateTime(block.timestamp);

    //     // vm.startPrank(priceFeedOwnerAddress);
    //     // // IPriceFeed(priceFeedAddress).updateChainlinkAggregator(wethAddress, address(mockChainlink));
    //     // IPriceFeed(priceFeedAddress).updateChainlinkAggregator(wbtcAddress, address(mockChainlink2));
    //     // vm.stopPrank();

    //     // uint256 rewardTokenGain = IStabilityPool(stabilityPoolAddress).getDepositorLQTYGain(address(wrappedProxy));

    //     // liquidateTroves(wbtcAddress);
    //     // // liquidateTroves(wethAddress);

    //     // wrappedProxy.harvest();
    //     // skip(timeToSkip);
    //     // uint256 sharePrice4 = vault.getPricePerFullShare();

    //     // wrappedProxy.getERNValueOfCollateralGain();

    //     // console.log("sharePrice1: ", sharePrice1);
    //     // console.log("sharePrice2: ", sharePrice2);
    //     // console.log("sharePrice3: ", sharePrice3);
    //     // console.log("sharePrice4: ", sharePrice4);
    //     // assertGt(sharePrice4, sharePrice1);
    // }

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
