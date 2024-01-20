// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { ERC4626Test } from "../helper/solmate-ERC4626.t.sol";

import { AdminModule } from "../../../../contracts/liquidity/adminModule/main.sol";
import { iToken } from "../../../../contracts/protocols/lending/iToken/main.sol";
import { LendingFactory } from "../../../../contracts/protocols/lending/lendingFactory/main.sol";
import { ILendingFactory } from "../../../../contracts/protocols/lending/interfaces/iLendingFactory.sol";
import { IIToken } from "../../../../contracts/protocols/lending/interfaces/iIToken.sol";
import { ILiquidity } from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { LendingRewardsRateModel } from "../../../../contracts/protocols/lending/lendingRewardsRateModel/main.sol";
import { Structs as AdminModuleStructs } from "../../../../contracts/liquidity/adminModule/structs.sol";
import { ILendingRewardsRateModel } from "../../../../contracts/protocols/lending/interfaces/iLendingRewardsRateModel.sol";
import { Structs as LendingRewardsRateModelStructs } from "../../../../contracts/protocols/lending/lendingRewardsRateModel/structs.sol";

import { Structs as LiquidityResolverStructs } from "../../../../contracts/periphery/resolvers/liquidity/structs.sol";
import { Handler } from "./handler.sol";
import { TestERC20 } from "../../testERC20.sol";
import { LiquidityBaseTest } from "../../liquidity/liquidityBaseTest.t.sol";
import { LiquidityUserModuleOperateTestSuite } from "../../liquidity/userModule/liquidityOperate.t.sol";
import { LiquidityCalcs } from "../../../../contracts/libraries/liquidityCalcs.sol";
import { LiquidityUserModuleBaseTest } from "../../liquidity/userModule/liquidityUserModuleBaseTest.t.sol";

import { ErrorTypes } from "../../../../contracts/liquidity/errorTypes.sol";
import { Error } from "../../../../contracts/liquidity/error.sol";

import { MockERC20 } from "solmate/src/test/utils/mocks/MockERC20.sol";
import { MockERC4626 } from "solmate/src/test/utils/mocks/MockERC4626.sol";

import "forge-std/Test.sol";

abstract contract ERC4626iTokenHelperTest is LiquidityBaseTest, LiquidityUserModuleBaseTest {
    MockERC20 asset;
    MockERC4626 token;
    ILiquidity liquidityProxy;
    LendingFactory factory;
    LendingRewardsRateModel rateModel;
    uint256 endTime_;
    uint256 startTime_;

    // ========= TEST FOR ERC4626 FROM SOLMATE

    function setUp() public virtual override(LiquidityBaseTest, LiquidityUserModuleBaseTest) {
        LiquidityBaseTest.setUp();
        liquidityProxy = ILiquidity(address(liquidity));
        factory = new LendingFactory(liquidityProxy, address(admin));
        vm.prank(admin);
        factory.setITokenCreationCode("iToken", type(iToken).creationCode);
        // Add factory to the list of auths so it can enable iTokens to provide liquidity
        vm.prank(admin);
        AdminModuleStructs.AddressBool[] memory auths = new AdminModuleStructs.AddressBool[](1);
        auths[0] = AdminModuleStructs.AddressBool(address(factory), true);
        liquidityProxy.updateAuths(auths);
        vm.prank(admin);
        token = MockERC4626(factory.createToken(address(USDC), "iToken", false));
        asset = MockERC20(address(USDC));
        _setDefaultRateDataV1(address(liquidityProxy), admin, address(asset));

        _setApproval(IERC20(address(asset)), address(token), alice);

        _setUserAllowancesDefault(address(liquidity), admin, address(USDC), address(token));
    }

    function activateRewardRateModel() internal returns (LendingRewardsRateModel, uint256, uint256) {
        // TODO: (Optional to improve) take default settings of rate model from TestSuite from rateModel tests
        uint256 decimals_ = 6;

        (, , , , , , , uint256 liquidityExchangePriceBefore, uint256 tokenExchangePriceBefore) = IIToken(address(token))
            .getData();

        uint256 startTime_ = block.timestamp + 3153600; // 10% of 1 year = 36.5 days
        uint256 endTime_ = startTime_ + 365 days;

        LendingRewardsRateModel rateModel = new LendingRewardsRateModel(
            decimals_,
            startTime_,
            endTime_,
            LendingRewardsRateModelStructs.RateDataParams({
                kink1: 10_000,
                kink2: 30_000,
                kink3: 350_000,
                rateZeroAtTVL: 1_000_000_000,
                rateAtTVLZero: 20 * 1e2,
                rateAtTVLKink1: 10 * 1e2,
                rateAtTVLKink2: 5 * 1e2,
                rateAtTVLKink3: 2 * 1e2
            })
        );

        vm.prank(admin);
        IIToken(address(token)).updateRewards(ILendingRewardsRateModel(address(rateModel)));

        LiquidityResolverStructs.OverallTokenData memory overallTokenData = resolver.getOverallTokenData(address(USDC));

        // Move time to startTime_
        vm.warp(startTime_);

        (, , , , , , , uint256 liquidityExchangePriceAfter, uint256 tokenExchangePriceAfter) = IIToken(address(token))
            .getData();

        // rewards return in percentage = rewardsRate * timeElapsed / SECONDS_PER_YEAR
        // rewards return in percentage = 20000000000000 * (34689601 - 34689601) / 31536000 (rewardRate proper calculation confirmed in lendingRewardsRateModel.t.sol)
        // rewards return in percentage = 20000000000000 * 0 / 31536000
        // rewards return in percentage = 0

        /*
        How to calculate borrow and supply exchange prices explanation:

        taking the same example and amounts
        DEFAULT_SUPPLY_AMOUNT = 1 ether and
        DEFAULT_BORROW_AMOUNT = 0.5 ether
        after the 1 year update the total supply will be
        1 ether * 103.875% = 1,03875 ether
        and total borrow will be
        0.5 ether * 107.75% = 0,53875 ether
        so from that we can get the new utilization
        which is total borrow / total supply. =  0,53875 / 1,03875 = ~51.865%. Note how this went up from previous 50%
        and borrow rate is a result of utilization so with higher utilization there is a higher borrow rate.
        borrow rate is depending on the following config (when leaving the default values, defined in liquidityTestHelpers.sol):

        uint256 constant DEFAULT_KINK = 80 * DEFAULT_PERCENT_PRECISION; // 80%
        uint256 constant DEFAULT_RATE_AT_ZERO = 4 * DEFAULT_PERCENT_PRECISION; // 4%
        uint256 constant DEFAULT_RATE_AT_KINK = 10 * DEFAULT_PERCENT_PRECISION; // 10%
        uint256 constant DEFAULT_RATE_AT_MAX = 150 * DEFAULT_PERCENT_PRECISION; // 150%

        borrow rate is y = mx +b where b = DEFAULT_RATE_AT_ZERO
        and for m*x , we can simply think if 80% is the total length from 0 to kink and over this period it increases from 4% at 0 to 10% at kink we can find out:
        how much of the total length we passed with utilization being at 51%: utilization / length = 51.86% / 80% = 64,825%
        so borrow rate will be: 64,825%  of the total 6% growth (4 at 0 to 10 at kink) + 4%. -> 64,825% * 0.6 + 4% = 3,8895% + 4% = 7.8895%
        so over 1 year the borrow rate is 7.8895% or for 36.5 days 10% of that so 0.78895%
        new borrow exchange price = oldBorrowExchangePrice * 100.78895% = 1077500000000 * 100,78895% = 1086000936250.
        For the supply exchange price, previously it was half of the increase of borrow exchange price because we were at exactly 50% utilization. But now it is 51.86% utilization so it will be that increase :
        0.78895% * 51.86% = 0,40914947%.
        new supply exchange price = oldSupplyExchangePrice * 100.40914947 = 1038750000000 * 100,40914947% = 1043000040119
        and to get to new total amounts afterwards simply multiply previous total amounts with new exchange prices again
        */

        return (rateModel, endTime_, startTime_);
    }

    function activateYieldWithDefaultValuesAndWarpTime(uint256 time) internal {
        activateYieldAndWarpTime(time, DEFAULT_SUPPLY_AMOUNT, DEFAULT_BORROW_AMOUNT);
    }

    function activateYieldAndWarpTime(uint256 time, uint256 supplyAmount, uint256 borrowAmount) internal {
        // alice supplies asset liquidity
        asset.mint(address(liquidity), 100 * 1e6);
        _setUserAllowancesDefault(address(liquidity), admin, address(asset), address(mockProtocol));
        address alice = address(0xB0FF);
        // alice supplies asset liquidity
        asset.mint(alice, supplyAmount);
        vm.prank(alice);
        asset.approve(address(mockProtocol), type(uint256).max);
        _supply(mockProtocol, address(asset), alice, supplyAmount);

        // alice borrows asset liquidity
        _borrow(mockProtocol, address(asset), alice, borrowAmount);

        // simulate passing time to accrue yield
        vm.warp(block.timestamp + time);

        address[] memory tokens = new address[](1);
        tokens[0] = address(asset);
        // update exchange prices at liquidity (open method)
        AdminModule(address(liquidity)).updateExchangePrices(tokens);
    }

    function initialDeposit(uint256 amount) internal {
        vm.prank(admin);
        factory.setAuth(alice, true);
        vm.prank(alice);
        asset.mint(alice, amount);
        asset.approve(address(token), type(uint256).max);
        vm.prank(admin);
        IIToken(address(token)).deposit(amount, admin);

        vm.prank(alice);
        IIToken(address(token)).approve(address(liquidity), type(uint256).max);

        vm.prank(bob);
        IIToken(address(token)).approve(address(liquidity), type(uint256).max);
    }
}

contract ERC4626iTokenTest is ERC4626iTokenHelperTest, ERC4626Test {
    // ========= TEST FOR ERC4626 STANDARD TESTS FROM SOLMATE

    function setUp() public virtual override(ERC4626iTokenHelperTest, ERC4626Test) {
        ERC4626iTokenHelperTest.setUp();
        vault = token;
        underlying = asset;
    }

    /// forge-config: default.invariant.fail-on-revert = false
    function invariantMetadata() public virtual override {
        assertEq(vault.name(), string.concat("Fluid Interest ", underlying.symbol()));
        assertEq(vault.symbol(), string.concat("fi", underlying.symbol()));
        assertEq(vault.decimals(), token.decimals());
    }

    function testMintZero() public virtual override {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__OperateAmountsZero)
        );
        vault.mint(0, address(this));
    }

    function testSingleDepositWithdraw(uint128 amount) public virtual override {
        vm.assume(amount <= uint128(type(int128).max));

        if (amount == 0) amount = 1;
        uint256 aliceUnderlyingAmount = amount;

        underlying.mint(alice, aliceUnderlyingAmount);

        vm.prank(alice);
        underlying.approve(address(vault), aliceUnderlyingAmount);
        assertEq(underlying.allowance(alice, address(vault)), aliceUnderlyingAmount);

        uint256 alicePreDepositBal = underlying.balanceOf(alice);

        vm.prank(alice);
        uint256 aliceShareAmount = vault.deposit(aliceUnderlyingAmount, alice);

        assertEq(aliceUnderlyingAmount, aliceShareAmount);
        assertEq(vault.previewWithdraw(aliceShareAmount), aliceUnderlyingAmount);
        assertEq(vault.previewDeposit(aliceUnderlyingAmount), aliceShareAmount);
        assertEq(vault.totalSupply(), aliceShareAmount);
        assertEq(vault.totalAssets(), aliceUnderlyingAmount);
        assertEq(vault.balanceOf(alice), aliceShareAmount);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), aliceUnderlyingAmount);
        assertEq(underlying.balanceOf(alice), alicePreDepositBal - aliceUnderlyingAmount);

        vm.prank(alice);
        try vault.withdraw(aliceUnderlyingAmount, alice, alice) {
            assertEq(vault.totalAssets(), 0);
            assertEq(vault.balanceOf(alice), 0);
            assertEq(vault.convertToAssets(vault.balanceOf(alice)), 0);
            assertEq(underlying.balanceOf(alice), alicePreDepositBal);
        } catch (bytes memory lowLevelData) {
            // we ignore cases when there is arithmetic error or withdrawal limit is reached // TODO: Check withdrawal limit?
            if (
                keccak256(abi.encodePacked(lowLevelData)) != keccak256(abi.encodePacked(stdError.arithmeticError)) &&
                keccak256(abi.encodePacked(lowLevelData)) !=
                keccak256(
                    abi.encodeWithSelector(
                        Error.FluidLiquidityError.selector,
                        ErrorTypes.UserModule__WithdrawalLimitReached
                    )
                )
            ) {
                assertEq(true, false);
            }
        }
    }

    function testSingleMintRedeem(uint128 amount) public virtual override {
        vm.assume(amount <= uint128(type(int128).max));
        if (amount == 0) amount = 1;

        uint256 aliceShareAmount = amount;

        underlying.mint(alice, aliceShareAmount);

        vm.prank(alice);
        underlying.approve(address(vault), aliceShareAmount);
        assertEq(underlying.allowance(alice, address(vault)), aliceShareAmount);

        uint256 alicePreDepositBal = underlying.balanceOf(alice);

        vm.prank(alice);
        uint256 aliceUnderlyingAmount = vault.mint(aliceShareAmount, alice);

        // Expect exchange rate to be 1:1 on initial mint.
        assertEq(aliceShareAmount, aliceUnderlyingAmount);
        assertEq(vault.previewWithdraw(aliceShareAmount), aliceUnderlyingAmount);
        assertEq(vault.previewDeposit(aliceUnderlyingAmount), aliceShareAmount);
        assertEq(vault.totalSupply(), aliceShareAmount);
        assertEq(vault.totalAssets(), aliceUnderlyingAmount);
        assertEq(vault.balanceOf(alice), aliceUnderlyingAmount);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), aliceUnderlyingAmount);
        assertEq(underlying.balanceOf(alice), alicePreDepositBal - aliceUnderlyingAmount);

        vm.prank(alice);
        try vault.redeem(aliceShareAmount, alice, alice) {
            assertEq(vault.totalAssets(), 0);
            assertEq(vault.balanceOf(alice), 0);
            assertEq(vault.convertToAssets(vault.balanceOf(alice)), 0);
            assertEq(underlying.balanceOf(alice), alicePreDepositBal);
        } catch (bytes memory lowLevelData) {
            // we ignore cases when there is arithmetic error or withdrawal limit is reached // TODO: Check withdrawal limit?
            if (
                keccak256(abi.encodePacked(lowLevelData)) != keccak256(abi.encodePacked(stdError.arithmeticError)) &&
                keccak256(abi.encodePacked(lowLevelData)) !=
                keccak256(
                    abi.encodeWithSelector(
                        Error.FluidLiquidityError.selector,
                        ErrorTypes.UserModule__WithdrawalLimitReached
                    )
                )
            ) {
                assertEq(true, false);
            }
        }
    }

    function testMultipleMintDepositRedeemWithdraw() public virtual override {
        // iToken scenario when rewards are not active:
        // A = Alice, B = Bob
        //  ________________________________________________________
        // | Vault shares | A share | A assets | B share | B assets |
        // |========================================================|
        // | 1. Alice mints 2000 shares (costs 2000 tokens)         |
        // |--------------|---------|----------|---------|----------|
        // |         2000 |    2000 |     2000 |       0 |        0 |
        // |--------------|---------|----------|---------|----------|
        // | 2. Bob deposits 4000 tokens (mints 4000 shares)        |
        // |--------------|---------|----------|---------|----------|
        // |         6000 |    2000 |     2000 |    4000 |     4000 |
        // |--------------|---------|----------|---------|----------|
        // | 3. Vault mutates by +3000 tokens...                    |
        // |    (simulated yield returned from strategy)...         |
        // |    NOTE: In case of iToken it doesnt change any        |
        // |                          parameters                    |
        // |--------------|---------|----------|---------|----------|
        // |         6000 |    2000 |     2000 |    4000 |     4000 |
        // |--------------|---------|----------|---------|----------|
        // | 4. Alice deposits 2000 tokens (mints 2000 shares)      |
        // |--------------|---------|----------|---------|----------|
        // |         8000 |    4000 |     4000 |    4000 |     4000 |
        // |--------------|---------|----------|---------|----------|
        // | 5. Bob mints 2000 shares            |
        // |    NOTE: Bob's assets spent got rounded up             |
        // |    NOTE: Alice's vault assets got rounded up           |
        // |--------------|---------|----------|---------|----------|
        // |        10000 |    4000 |     4000 |    6000 |     6000 |
        // |--------------|---------|----------|---------|----------|
        // | 6. Vault mutates by +3000 tokens...                    |
        // |    (simulated yield returned from strategy)            |
        // |    NOTE: In case of iToken it doesnt change any        |
        // |                          parameters                    |
        // |--------------|---------|----------|---------|----------|
        // |        10000 |    4000 |     4000 |    6000 |     6000 |
        // |--------------|---------|----------|---------|----------|
        // | 7. Alice redeem 1333 shares (1333 assets)              |
        // |--------------|---------|----------|---------|----------|
        // |         8667 |    2667 |     2667 |    6000 |     6000 |
        // |--------------|---------|----------|---------|----------|
        // | 8. Bob withdraws 2928 assets (2928 shares)             |
        // |--------------|---------|----------|---------|----------|
        // |         5738 |    2667 |     2667 |    3071 |     3071 |
        // |--------------|---------|----------|---------|----------|
        // | 9. Alice withdraws 2667 assets (2667 shares)           |
        // |    NOTE: Bob's assets have been rounded back up        |
        // |--------------|---------|----------|---------|----------|
        // |         3071 |       0 |        0 |    3071 |     3071 |
        // |--------------|---------|----------|---------|----------|
        // | 10. Bob redeem 3071 shares (3071 tokens)               |
        // |--------------|---------|----------|---------|----------|
        // |            0 |       0 |        0 |       0 |        0 |
        // |______________|_________|__________|_________|__________|

        // Zero balances
        vm.prank(alice);
        underlying.burn(address(alice), underlying.balanceOf(alice));
        vm.prank(bob);
        underlying.burn(address(bob), underlying.balanceOf(bob));

        uint256 mutationUnderlyingAmount = 3000;

        underlying.mint(alice, 4000);

        vm.prank(alice);
        underlying.approve(address(vault), 4000);

        assertEq(underlying.allowance(alice, address(vault)), 4000);

        underlying.mint(bob, 7001);

        vm.prank(bob);
        underlying.approve(address(vault), 7001);

        assertEq(underlying.allowance(bob, address(vault)), 7001);

        // 1. Alice mints 2000 shares (costs 2000 tokens)
        vm.prank(alice);
        uint256 aliceUnderlyingAmount = vault.mint(2000, alice);

        uint256 aliceShareAmount = vault.previewDeposit(aliceUnderlyingAmount);

        // Expect to have received the requested mint amount.
        assertEq(aliceShareAmount, 2000);
        assertEq(vault.balanceOf(alice), aliceShareAmount);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), aliceUnderlyingAmount);
        assertEq(vault.convertToShares(aliceUnderlyingAmount), vault.balanceOf(alice));

        // Expect a 1:1 ratio before mutation.
        assertEq(aliceUnderlyingAmount, 2000);

        // Sanity check.
        assertEq(vault.totalSupply(), aliceShareAmount);
        assertEq(vault.totalAssets(), aliceUnderlyingAmount);

        // 2. Bob deposits 4000 tokens (mints 4000 shares)
        vm.prank(bob);
        uint256 bobShareAmount = vault.deposit(4000, bob);
        uint256 bobUnderlyingAmount = vault.previewWithdraw(bobShareAmount);

        // Expect to have received the requested underlying amount.
        assertEq(bobUnderlyingAmount, 4000);
        assertEq(vault.balanceOf(bob), bobShareAmount);
        assertEq(vault.convertToAssets(vault.balanceOf(bob)), bobUnderlyingAmount);
        assertEq(vault.convertToShares(bobUnderlyingAmount), vault.balanceOf(bob));

        // Expect a 1:1 ratio before mutation.
        assertEq(bobShareAmount, bobUnderlyingAmount);

        // Sanity check.
        uint256 preMutationShareBal = aliceShareAmount + bobShareAmount;
        uint256 preMutationBal = aliceUnderlyingAmount + bobUnderlyingAmount;
        assertEq(vault.totalSupply(), preMutationShareBal);
        assertEq(vault.totalAssets(), preMutationBal);
        assertEq(vault.totalSupply(), 6000);
        assertEq(vault.totalAssets(), 6000);

        // 3. Vault mutates by +3000 tokens...                    |
        //    (simulate donation)...
        // The Vault now contains more tokens than deposited but this should have no effect on the totalAssets or
        // share price etc. All values should stay the same as only balance in Liquidity contains, not in vault.
        underlying.mint(address(vault), mutationUnderlyingAmount);
        assertEq(vault.totalSupply(), preMutationShareBal);
        assertEq(vault.totalAssets(), preMutationBal);
        assertEq(vault.balanceOf(alice), aliceShareAmount);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), aliceUnderlyingAmount);
        assertEq(vault.balanceOf(bob), bobShareAmount);
        assertEq(vault.convertToAssets(vault.balanceOf(bob)), bobUnderlyingAmount);

        // 4. Alice deposits 2000 tokens

        vm.prank(alice);
        vault.deposit(2000, alice);

        assertEq(vault.totalSupply(), 8000);

        assertEq(vault.balanceOf(alice), 4000);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), 4000);
        assertEq(vault.balanceOf(bob), 4000);
        assertEq(vault.convertToAssets(vault.balanceOf(bob)), 4000);

        // 5. Bob mints 2000 shares (costs 2000 assets)
        // NOTE: Bob's assets spent got rounded up
        // NOTE: Alices's vault assets got rounded up
        vm.prank(bob);
        vault.mint(2000, bob);

        assertEq(vault.totalSupply(), 10000);
        assertEq(vault.balanceOf(alice), 4000);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), 4000);
        assertEq(vault.balanceOf(bob), 6000);
        assertEq(vault.convertToAssets(vault.balanceOf(bob)), 6000);

        // Sanity checks:
        // Alice and bob should have spent all their tokens now

        uint256 aliceSpent = 2000 + 2000;
        uint256 bobSpent = 4000 + 2000;
        assertEq(underlying.balanceOf(alice), 4000 - aliceSpent);
        assertEq(underlying.balanceOf(bob), 7001 - bobSpent);
        // NOW === END

        assertEq(vault.totalAssets(), aliceSpent + bobSpent);

        // 6. Vault mutates by +3000 tokens
        // NOTE: Vault holds 10000 tokens
        underlying.mint(address(vault), mutationUnderlyingAmount); // in this case I doesnt change exchange price and totalAssets number
        assertEq(vault.totalAssets(), 10000);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), 4000);
        assertEq(vault.convertToAssets(vault.balanceOf(bob)), 6000);

        vm.prank(alice);
        vault.redeem(1333, alice, alice);

        // 7. Alice redeem 1333 shares (1333 assets)
        assertEq(underlying.balanceOf(alice), 1333);
        assertEq(vault.totalSupply(), 8667);
        assertEq(vault.totalAssets(), 8667);
        assertEq(vault.balanceOf(alice), 2667);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), 2667);
        assertEq(vault.balanceOf(bob), 6000);
        assertEq(vault.convertToAssets(vault.balanceOf(bob)), 6000);

        vm.prank(bob);
        vault.withdraw(2929, bob, bob);

        // 8. Bob withdraws 2929 assets (2929 shares)
        assertEq(underlying.balanceOf(bob), 3930);
        assertEq(vault.totalSupply(), 5738);
        assertEq(vault.totalAssets(), 5738);
        assertEq(vault.balanceOf(alice), 2667);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), 2667);
        assertEq(vault.balanceOf(bob), 3071);
        assertEq(vault.convertToAssets(vault.balanceOf(bob)), 3071);

        // 9. Alice withdraws 2667 assets (2667 shares)
        // NOTE: Bob's assets have been rounded back up
        vm.prank(alice);
        vault.withdraw(2667, alice, alice);
        assertEq(underlying.balanceOf(alice), 4000);
        assertEq(vault.totalSupply(), 3071);
        assertEq(vault.totalAssets(), 3071);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), 0);
        assertEq(vault.balanceOf(bob), 3071);
        assertEq(vault.convertToAssets(vault.balanceOf(bob)), 3071);

        // 10. Bob redeem 3071 shares (3071 tokens)
        vm.prank(bob);
        vault.redeem(3071, bob, bob);
        assertEq(underlying.balanceOf(bob), 7001);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), 0);
        assertEq(vault.balanceOf(bob), 0);
        assertEq(vault.convertToAssets(vault.balanceOf(bob)), 0);
        // Sanity check
        assertEq(underlying.balanceOf(address(vault)), 6000);
    }

    function testMultipleMintDepositRedeemWithdraw_WithActiveRewardsAndYield() public virtual {
        // A = Alice, B = Bob
        //  ______________________________________________________________
        // | Vault shares | A share | A assets | B share | B assets       |
        // |==============================================================|
        // |------------|-----------|-----------|-----------|-------------|
        // | 0. Initial state before any actions                          |
        // |------------|-----------|-----------|-----------|-------------|
        // |          0 |         0 |         0 |         0 |           0 |
        // |------------|-----------|-----------|-----------|-------------|
        // | 1. Activate yield and warp time +1 year                      |
        // |------------|-----------|-----------|-----------|-------------|
        // | 2. Activate rewards and warp time 10% of 1 year (36.5 days)  |
        // |------------|-----------|-----------|-----------|-------------|
        // | 3. Alice mints 2000 shares (costs 2086 tokens)               |
        // |------------|-----------|-----------|-----------|-------------|
        // |       2000 |      2000 |    2086   |         0 |           0 |
        // |------------|-----------|-----------|-----------|-------------|
        // | 4. Bob deposits 24000 tokens (mints 23010 shares)            |
        // |------------|-----------|-----------|-----------|-------------|
        // |      25010 |      2000 |    2086   |     23010 |       24000 |
        // |------------|-----------|-----------|-----------|-------------|
        // | 5. Vault mutates by +3000 tokens                             |
        // |    (simulated directly received underlying funds)            |
        // |------------|-----------|-----------|-----------|-------------|
        // |      25010 |      2000 |    2086   |     23010 |       24000 |
        // |------------|-----------|-----------|-----------|-------------|
        // | 6. Alice deposits 2086 tokens (mints 2000 shares)            |
        // |------------|-----------|-----------|-----------|-------------|
        // |      27010 |      4000 |    4172   |     23010 |       24000 |
        // |------------|-----------|-----------|-----------|-------------|
        // | 7. Bob mints 2000 shares  (costs 2086 tokens)                |
        // |------------|-----------|-----------|-----------|-------------|
        // |      29010 |      4000 |    4172   |     25010 |       26086 |
        // |------------|-----------|-----------|-----------|-------------|
        // | 8. Supply add 1 ether and borrow 0.5 and warp 20% of the year|
        // |------------|-----------|-----------|-----------|-------------|
        // | 9. Bob deposits 1000 tokens  (gets 941 shares)               |
        // |------------|-----------|-----------|-----------|-------------|
        // |      29951 |      4000 |    4246   |     25951 |       27553 |
        // |------------|-----------|-----------|-----------|-------------|
        // | 10. Alice redeems 1333 shares (est. 1415 tokens)             |
        // |------------|-----------|-----------|-----------|-------------|
        // |      28618 |      2667 |    2831   |     25951 |       27553 |
        // |------------|-----------|-----------|-----------|-------------|
        // | 11. Bob withdraws 200 tokens (est. 189 shares)                |
        // |------------|-----------|-----------|-----------|-------------|
        // |      28429 |      2667 |    2831   |     25762 |       27352 |
        // |------------|-----------|-----------|-----------|-------------|
        // | 12. Warp 50% of the year                                     |
        // |------------|-----------|-----------|-----------|-------------|
        // | 13. Alice withdraws 1000 tokens (est. 902 shares)            |
        // |------------|-----------|-----------|-----------|-------------|
        // |      27527 |      1765 |     1958  |     25762 |       28581 |
        // |------------|-----------|-----------|-----------|-------------|
        // | 14. Bob redeems 3071 shares (est. 3407 tokens)               |
        // |------------|-----------|-----------|-----------|-------------|
        // |      24456 |      1765 |     1958  |     22691 |       25174 |
        // |____________|___________|___________|___________|_____________|
        // 1.
        activateYieldWithDefaultValuesAndWarpTime(PASS_1YEAR_TIME);

        // to get borrow rate used for exchange prices update, this is the rate active for utilization BEFORE payback:
        // utilization = DEFAULT_BORROW_AMOUNT * FOUR_DECIMALS / DEFAULT_SUPPLY_AMOUNT; -> 50%
        // annual borrow rate for default test data with default values see {TestHelpers}, at utilization 50%:
        // 4% base rate at 0% utilization, rate grows 6% from 0% to kink at 80%
        // -> so for every 8% in utilization incrase, rate grows 0.6%.
        // at utilization 50% it's 4% + 3.75% (50 / 8 * 0.6%) = 7.75%
        // uint256 borrowRateBeforePayback = 775; // 7.75% in 1e2 precision
        // uint256 supplyExchangePrice = 1038750000000; // increased half of 7.75% -> 3.875% (because half of supply is borrowed out)
        // uint256 borrowExchangePrice = 1077500000000; // increased 7.75%

        // supply exchange price: 103.875%
        // borrow exchange price: 107.75%

        // after the 1 year update the total supply will be
        // 1 ether * 103.875% = 1,03875 ether
        // and total borrow will be
        // 0.5 ether * 107.75% = 0,53875 ether

        // 2.
        (rateModel, endTime_, startTime_) = activateRewardRateModel(); // rate model
        // initial total supply (after 1 year) = 1,03875 ether
        // initial total borrow (after 1 year) = 0,53875 ether

        // additional supply: 0 ether
        // additional borrow: 0 ether

        // new total supply = 1.0834058625 ether (no additional supply amount)
        // new total borrow = 0.5850771125 ether (no additional supply amount)

        // new utilization rate = 0.53875 / 1.03875 = 51.86%

        // borrow rate = base rate + (utilization / kink) * (rate at kink - base rate)
        // borrow rate = 4% + (51.86%/80%) * (10% - 4%)
        // borrow rate = 4% + 0.6482 * 6%
        // borrow rate = 7.8892%

        // so after 10% of year (36.5 days) its 0.78892% (7.8892% * 1 / 10)

        // new borrow exchange price = oldBorrowExchangePrice * 100.78892% = 1077500000000 * 100.78892% = 1086000613000
        // For the supply exchange price, previously it was half of the increase of borrow exchange price because we were at exactly 50% utilization. But now it is 51.86% utilization so it will be that increase:
        // 0.78892% * 51.86% = 0.4091%.
        // new supply exchange price = oldSupplyExchangePrice * 100.4091% = 1038750000000 * 100.4091% = 1042999526250

        // supply exchange price: 104.2994922510%
        // borrow exchange price: 108.5990700000%

        // after next 1/10 year (from activateRewardRateModel function) update the total supply will be
        // 1 ether * 104.2994922510% = 1.04299492251 ether
        // and total borrow will be
        // 0.5 ether * 108.5990700000%  = 0.54299535 ether

        LiquidityResolverStructs.OverallTokenData memory overallTokenData = resolver.getOverallTokenData(
            address(asset)
        );
        assertEq(overallTokenData.borrowExchangePrice, 1085990700000);
        assertEq(overallTokenData.supplyExchangePrice, 1042994922510);
        assertEq(overallTokenData.totalSupply, 1042994922510000000);

        uint256 initAliceBalance = 1e50 ether;
        uint256 initBobBalance = 1e50 ether;

        uint256 tolerance = 1e2;
        uint256 mutationUnderlyingAmount = 3000;
        uint256 aliceMintSharesAmount = 2000;
        uint256 aliceShareAmount = vault.previewDeposit(2086);

        // 3.
        aliceMintsShares(tolerance, aliceMintSharesAmount, aliceShareAmount);

        uint256 preMutationShareBal = aliceMintSharesAmount + 23010;
        uint256 preMutationBal = 2086 + 24000;

        uint256 bobUnderlyingAmount = vault.previewRedeem(23010);
        // 4.
        bobDepositsTokens(tolerance, aliceMintSharesAmount, preMutationShareBal, preMutationBal, bobUnderlyingAmount);
        // 5.
        simulateVaultMutationByDirectTokenReceipt(
            tolerance,
            mutationUnderlyingAmount,
            preMutationShareBal,
            preMutationBal,
            aliceShareAmount,
            bobUnderlyingAmount
        );
        // 6.
        aliceDepositsTokensAgain(tolerance);
        // 7.
        bobMintsShares(initAliceBalance, initBobBalance, tolerance);

        overallTokenData = resolver.getOverallTokenData(address(asset));

        // 8.
        activateYieldAndWarpTime((PASS_1YEAR_TIME * 2) / 10, 1 ether, 0.5 ether);
        // old borrow exchange price = 1085990700000;
        // old supply exchange price = 1042994922510;

        // initial total supply (after 1.1 years) = 1.04299492251 ether
        // initial total borrow (after 1.1 years) = 0.54299535 ether

        // additional supply: 1 ether
        // additional borrow: 0.5 ether

        // new total supply = 1.04299492251 ether + 1 ether = 2.04299492251 ether
        // new total borrow = 0.54299535 ether + 0.5 ether = 1.04299535 ether

        // new utilization rate = 1.04299535 / 2.04299492251 = 51.0522732%

        // borrow rate = base rate + (utilization / kink) * (rate at kink - base rate)
        // borrow rate = 4% + (51.0522732%/80%) * (10% - 4%)
        // borrow rate = 4% + 0.63815342 * 6%
        // borrow rate = 7.82892052%

        // so after 20% of year (70 days) its 1.5657841% (7.82892052% * 2 / 10)

        // new borrow exchange price = oldBorrowExchangePrice * 101.5657841% = 1085990700000 * 101.5657841% = 1102994969708
        // For the supply exchange price, previously it was half of the increase of borrow exchange price because we were at exactly 50% utilization. But now it is 51.0522732% utilization so it will be that increase:
        // 1.5657841% * 51.0522732% = 0.7993684%.
        // new supply exchange price = oldSupplyExchangePrice * 100.7993684% = 1042994922510 * 100.7993684% = 1051332294334

        overallTokenData = resolver.getOverallTokenData(address(asset));
        assertEq(overallTokenData.borrowExchangePrice, 1102975594548); // 1102994969708 can be small inaccuracy thats why its 1102975594548
        assertEq(overallTokenData.supplyExchangePrice, 1051322423430); // 1051332294334 can be small inaccuracy thats why its 1051322423430

        (, , , , , , , uint256 liquidityExchangePrice, uint256 tokenExchangePrice) = IIToken(address(token)).getData();
        assertEq(liquidityExchangePrice, 1051322423430); // 1051662836113 can be small inaccuracy thats why its 1051322423430
        assertEq(block.timestamp, 40996801);

        // rewards return in percentage = rewardsRate * timeElapsed / SECONDS_PER_YEAR
        // rewardsRate = 4997590625000 (~5%) at very close to 30k TVL (kink2)
        // rewards return in percentage = 4997590625000 * (40996801 - 34689601) / 31536000 (rewardRate proper calculation confirmed in lendingRewardsRateModel.t.sol)
        // rewards return in percentage = 4997590625000 * 6307200 / 31536000
        // rewards return in percentage = 999518125000 (~20% of 5% -> ~1%)

        // total return in percentage (reward + yield) =
        //  rewards return in percentage + ((new liquidity exchange price - old liquidity exchange price) / old liquidity exchange price) =
        //  0.999518125000% + (1.051322423430 - 1.042994922510) / 1.042994922510 * 1e14 = 1,797940124980% (= ~0.9995% + ~0.79842%)

        // token exchange price_ = oldTokenExchangePrice_ + oldTokenExchangePrice_ * totalReturnInPercent_ / 1e14
        // token exchange price_ = 1.042994922510 + 1.042994922510 * 1,797940124980%
        // token exchange price_ = 1.042994922510 + 0,0187524242133 = 1,061747346723

        assertEq(tokenExchangePrice, 1061747346723);

        // new total supply:  2.04299492251 ether * 100.79842% = 2.059306602570304342 ether
        assertEq(overallTokenData.totalSupply, 2059306643429836042); // 2059306602570304342 can be small inaccuracy thats why its 2059306643429836042
        // new total borrow:  1.04299535 ether * 101.5657841% = 1.05932640535403935 ether
        assertEq(overallTokenData.totalBorrow, 1059307797274000020); // 105932640535403935 can be small inaccuracy thats why its 1059307797274000020

        // 9.
        bobDepositsSharesAgain(initAliceBalance, initBobBalance, tolerance);
        // 10.
        aliceRedeemsShares(initAliceBalance, initBobBalance, tolerance);
        // 11.
        bobWithdrawsTokens(initAliceBalance, initBobBalance, tolerance);
        overallTokenData = resolver.getOverallTokenData(address(asset));

        console2.log("totalSupply");
        console2.log(overallTokenData.totalSupply);
        console2.log("totalBorrow");
        console2.log(overallTokenData.totalBorrow);
        // 12.
        activateYieldWithDefaultValuesAndWarpTime(PASS_1YEAR_TIME / 2);
        // old borrow exchange price = 1102975594548;
        // old supply exchange price = 1051322423430;
        // initial total supply (after 1.3 years) = 2.059306602570304342 ether
        // initial total borrow (after 1.3 years) = 1.05932640535403935 ether

        // additional supply: 1 ether
        // additional borrow: 0.5 ether

        // new total supply = 2.059306602570304342 ether + 1 ether = 3.059306602570304342 ether
        // new total borrow = 1.05932640535403935 ether + 0.5 ether = 1.55932640535403935 ether

        // new utilization = 1.55932640535403935 / 3.059306602570304342 = 49.072889408354103965632940%

        // after 182.5 days (50% year)
        // borrow rate = base rate + (utilization / kink) * (rate at kink - base rate)
        // borrow rate = 4% + (50.96992906967732%/80%) * (10% - 4%)
        // borrow rate = 4% + 0.637124113370967 * 6%
        // borrow rate = 7.822744%

        // so after 50% of year its 3.911372% (7.822744%% * 5 / 10)

        // new borrow exchange price = oldBorrowExchangePrice * 103.911372% = 1102975594548 * 103.911372% = 1146117073119
        // For the supply exchange price on 50.96992906967732% utilization so it will be that increase:
        // 3.911372% * 50.96992906967732% = 1.993624%.
        // new supply exchange price = oldSupplyExchangePrice * 101.993624% = 1051322423430 * 101.993624% = 1072281839580

        overallTokenData = resolver.getOverallTokenData(address(asset));

        assertEq(overallTokenData.borrowExchangePrice, 1146101940294); // 1146117073119
        assertEq(overallTokenData.supplyExchangePrice, 1072270401192); // 1072281839580

        (, , , , , , , liquidityExchangePrice, tokenExchangePrice) = IIToken(address(token)).getData();
        assertEq(liquidityExchangePrice, 1072270401192); //small inaccuracy 1073313313753
        assertEq(block.timestamp, 56764801);

        // rewards return in percentage = rewardsRate * timeElapsed / SECONDS_PER_YEAR
        // rewards return in percentage = 4998275000000 * (56764801 - 40996801) / 31536000 (rewardRate proper calculation confirmed in lendingRewardsRateModel.t.sol)
        // rewards return in percentage = 4998275000000 * 15768000 / 31536000
        // rewards return in percentage = 2499137500000

        //  total return in percentage (reward + yield) =
        //  rewards return in percentage + ((new liquidity exchange price - old liquidity exchange price) / old liquidity exchange price) =
        //  2.499137500000% + (1.072270401192 - 1.051322423430) / 1.051322423430 = ~2.4991% + ~1.9925% = 4.4916%

        // token exchange price_ = oldTokenExchangePrice_ + oldTokenExchangePrice_ * totalReturnInPercent_ / 1e14
        // token exchange price_ = 1.061747346723 + 1.061747346723 * 4.4916%
        // token exchange price_ = 1.061747346723 + 0.047689443825410268
        // token exchange price_ = 1.109436790548410268

        assertEq(tokenExchangePrice, 1109437570931); // small calculated inaccuracy acceptable

        // new total supply:  3.059306602570304342 ether * 101.9925% = 3.12026328662651765601435 ether
        assertEq(overallTokenData.totalSupply, 3120264429647903268);
        // new total supply:  1.55932640535403935 ether * 103.911372% = 3.12026328662651765601435 ether
        assertEq(overallTokenData.totalBorrow, 1620276732146244560);

        // 13.
        aliceWithdrawsTokens(initAliceBalance, initBobBalance, tolerance);
        // 14.
        bobRedeemsShares(initAliceBalance, initBobBalance, tolerance);
    }

    function aliceMintsShares(uint256 tolerance, uint256 aliceMintSharesAmount, uint256 aliceShareAmount) internal {
        // 3. Alice mints 2000 shares
        //    totalReturnInPercent_ = (rewardsRate_ * (block.timestamp - _lastUpdateTimestamp)) / _SECONDS_PER_YEAR;
        //    totalReturnInPercent_ = (20000000000000 * (34689601 - 34689601)) / 31536000;
        //    totalReturnInPercent_ = 0

        //    newTokenExchangePrice_ = oldTokenExchangePrice_ + ((oldTokenExchangePrice_ * 0) / _EXCHANGE_PRICES_PRECISION);
        //    newTokenExchangePrice_ = 1042994922510          + ((1038750000000          * 0       ) / 1000000000000);
        //    newTokenExchangePrice_ = 1042994922510;

        //    shares = 2000.mulDivUp(tokenExchangePrice_, 1000000000000);
        //    shares = 2000.mulDivUp(1042994922510, 1000000000000) = 2085.98984502 and up 2086
        //    cost = 2086 tokens
        vm.prank(alice);
        underlying.mint(alice, 2086);
        vm.prank(alice);
        vault.mint(2000, alice);

        // Expect to have received the requested mint amount.
        assertEq(aliceShareAmount, aliceMintSharesAmount);
        assertEq(vault.balanceOf(alice), aliceShareAmount);
        assertApproxEqAbs(vault.convertToAssets(vault.balanceOf(alice)), 2086, 1);
        assertEq(vault.convertToShares(2086), vault.balanceOf(alice));

        // Sanity check.
        assertEq(vault.totalSupply(), aliceShareAmount); // totalAssets function does round down

        assertApproxEqAbs(vault.totalAssets(), 2086, tolerance, "Conversion inaccuracy exceeded tolerance");
    }

    function bobDepositsTokens(
        uint256 tolerance,
        uint256 aliceMintSharesAmount,
        uint256 preMutationShareBal,
        uint256 preMutationBal,
        uint256 bobUnderlyingAmount
    ) internal {
        // 4. Bob deposits 24000 tokens (mints 23010 shares)
        //    bobShareAmount = assets * tokenExchangePrice;
        //    bobShareAmount = 24000  / 1.042994922510000000 = 23010.65 and down 23010
        //    bobShareAmount = 23010;

        //    newTokenExchangePrice_ = oldTokenExchangePrice_ + ((oldTokenExchangePrice_ * totalReturnInPercent_) / _EXCHANGE_PRICES_PRECISION);
        //    newTokenExchangePrice_ = 10429941042994922510          + ((1000000000000          * 0       ) / 1000000000000);
        //    newTokenExchangePrice_ = 10429941042994922510;

        vm.prank(bob);
        underlying.mint(bob, 24000);
        vm.prank(bob);
        underlying.approve(address(vault), 24000);
        vm.prank(bob);
        vault.deposit(24000, bob);

        // Expect to have received the shares  amount.
        assertEq(vault.balanceOf(bob), 23010, "2. bob deposit vault shares not equal 23010");

        // expect underlying amount at redeem to match deposited token amount
        assertApproxEqAbs(bobUnderlyingAmount, 24000, tolerance, "Conversion inaccuracy exceeded tolerance");

        // converting from shares to assets (or vice versa), the maximum inaccuracy are 2 units:

        // 1 unit of shares when using mulDivDown for assets to shares conversion.
        // 1 unit of assets when using mulDivUp for shares to assets conversion.
        // less this time because of more assets in the pool
        // assets = shares_.mulDivDown(tokenExchangePrice_, _EXCHANGE_PRICES_PRECISION)
        // assets = 23010 * 1547945205479 / 1000000000000 = 23999,34 and down = 23999
        // assets = 23999

        assertApproxEqAbs(
            vault.convertToAssets(vault.balanceOf(bob)),
            23999,
            tolerance,
            "Conversion inaccuracy exceeded tolerance"
        );
        assertEq(vault.convertToShares(24000), 23010);

        // Sanity check.
        assertEq(vault.totalSupply(), preMutationShareBal);
        assertApproxEqAbs(vault.totalAssets(), preMutationBal, tolerance, "Conversion inaccuracy exceeded tolerance");
    }

    function simulateVaultMutationByDirectTokenReceipt(
        uint256 tolerance,
        uint256 mutationUnderlyingAmount,
        uint256 preMutationShareBal,
        uint256 preMutationBal,
        uint256 aliceShareAmount,
        uint256 bobUnderlyingAmount
    ) internal {
        // 5. Vault mutates by +3000 tokens...
        //    (simulated directly recieved underlying funds)...
        underlying.mint(address(vault), mutationUnderlyingAmount);
        assertEq(vault.totalSupply(), preMutationShareBal);
        assertApproxEqAbs(vault.totalAssets(), preMutationBal, tolerance, "Conversion inaccuracy exceeded tolerance");
        assertEq(vault.balanceOf(alice), aliceShareAmount);

        // convertToAssets function does round down
        assertApproxEqAbs(
            vault.convertToAssets(vault.balanceOf(alice)),
            2086,
            tolerance,
            "Conversion inaccuracy exceeded tolerance"
        );
        assertEq(vault.balanceOf(bob), 23010);
        assertEq(vault.previewRedeem(vault.balanceOf(bob)), bobUnderlyingAmount);
    }

    function aliceDepositsTokensAgain(uint256 tolerance) internal {
        // 6. Alice deposits 2000 tokens

        vm.prank(alice);
        underlying.mint(alice, 2086);
        vm.prank(alice);
        vault.deposit(2086, alice); // alice deposit second half of her tokens. It should mint 2000 shares for her

        assertEq(vault.totalSupply(), vault.balanceOf(bob) + vault.balanceOf(alice));

        assertEq(vault.balanceOf(alice), 4000);
        assertApproxEqAbs(
            vault.convertToAssets(vault.balanceOf(alice)),
            2086 * 2,
            tolerance,
            "Conversion inaccuracy exceeded tolerance"
        );
        assertEq(vault.balanceOf(bob), 23010);
        assertApproxEqAbs(
            vault.convertToAssets(vault.balanceOf(bob)),
            24000,
            tolerance,
            "Conversion inaccuracy exceeded tolerance"
        );
    }

    function bobMintsShares(uint256 initAliceBalance, uint256 initBobBalance, uint256 tolerance) internal {
        // 7. Bob mints 2000 shares (costs 2086 assets)
        // NOTE: Bob's assets spent got rounded up
        // NOTE: Alices's vault assets got rounded up
        vm.prank(bob);
        underlying.mint(bob, 2086);
        vm.prank(bob);
        underlying.approve(address(vault), 2086);
        vm.prank(bob);
        vault.mint(2000, bob);
        assertEq(vault.totalSupply(), 23010 + 4000 + 2000); // 4000 alice's shares and 2000 bob's shares from second deposit
        assertEq(vault.balanceOf(alice), 4000);
        assertApproxEqAbs(
            vault.convertToAssets(vault.balanceOf(alice)),
            2086 * 2,
            tolerance,
            "Conversion inaccuracy exceeded tolerance"
        );
        assertEq(vault.balanceOf(bob), 23010 + 2000);
        assertApproxEqAbs(
            vault.convertToAssets(vault.balanceOf(bob)),
            24000 + 2086,
            tolerance,
            "Conversion inaccuracy exceeded tolerance"
        );

        // Sanity checks:
        // Alice and bob should have spent all their tokens now
        assertEq(underlying.balanceOf(alice), 0 + initAliceBalance);
        assertEq(underlying.balanceOf(bob), 0 + initBobBalance);

        assertApproxEqAbs(
            vault.totalAssets(),
            24000 + 2086 + 2086 + 2086, // bob two deposits + alices two deposits
            tolerance,
            "Conversion inaccuracy exceeded tolerance"
        );
    }

    function bobDepositsSharesAgain(uint256 initAliceBalance, uint256 initBobBalance, uint256 tolerance) internal {
        // 9. Bob deposits 1000 assets (gets 941 shares)
        // NOTE: As its time warp the is new tokenExchangePrice
        //shares amount = assets * tokenExchangePrice
        //shares amount = 1000 / 1.061747346723 = 941.84365337612724167719276245536255170895701500950498080936846427 and down = 941
        vm.prank(bob);
        underlying.mint(bob, 1000);
        vm.prank(bob);
        underlying.approve(address(vault), 1000);
        vm.prank(bob);
        vault.deposit(1000, bob);
        (, , , , , , uint256 liquidityBalance_, uint256 liquidityExchangePrice_, uint256 tokenExchangePrice_) = IIToken(
            address(token)
        ).getData();

        assertEq(vault.totalSupply(), 23010 + 4000 + 2000 + 941); // 4000 alice's shares and 2000 bob's shares from second deposit and 941 from bob's latest deposit
        assertEq(vault.balanceOf(alice), 4000);
        // assets = 4000 * 1.061747346723 = 4246.989386892 and down 4246
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), 4246);
        assertEq(vault.balanceOf(bob), 23010 + 2000 + 941); // 941 from bob's latest deposit
        // shares = 23010 + 2000 + 941 = 25951
        // assets = 25951 * 1.061747346723 = 27553.405394808573 and down 27553
        assertEq(vault.convertToAssets(vault.balanceOf(bob)), 27553);

        // Sanity checks:
        // Alice and bob should have spent all their tokens now

        assertEq(underlying.balanceOf(alice), 0 + initAliceBalance);
        assertEq(underlying.balanceOf(bob), 0 + initBobBalance);
        // bob shares =  23010 + 2000 + 941 = 25951
        // alice shares = 4000
        // total assets = (bob shares + alice shares) * token exchange price = (25951 + 4000) * 1.061747346723  = 31800.394781700573 and down = 31800
        assertEq(vault.totalAssets(), 31800);
    }

    function aliceRedeemsShares(uint256 initAliceBalance, uint256 initBobBalance, uint256 tolerance) internal {
        // 10. Alice redeem 1333 shares
        // assets  = shares * token price exchange
        // assets  = 1333 * 1.061747346723 = 1415.309213181759 and down 1415
        vm.prank(alice);
        vault.redeem(1333, alice, alice);

        assertEq(underlying.balanceOf(alice), 1415 + initAliceBalance);
        assertEq(vault.totalSupply(), 23010 + 2667 + 2000 + 941); // 2667 because alice had 4000 and after redeem it is 2667
        // bob shares =  23010 + 2000 + 941 = 25951
        // alice shares = 4000 - 1333 = 2667
        // total assets = (bob shares + alice shares) * token exchange price = (25951 + 2667) * 1.061747346723  = 30385.085568518814 and down = 30385
        assertEq(vault.totalAssets(), 30385);
        assertEq(vault.balanceOf(alice), 2667);

        // alice shares = 2667
        // assets = 2667 * 1.061747346723 = 2831.680173710241 and down 2831
        // nothing changes for bob
        assertEq(vault.balanceOf(bob), 23010 + 2000 + 941);
        // bob shares =  23010 + 2000 + 941 = 25951
        // assets = 25951 * 1.061747346723 = 27553.405394808573 and down 27553
        assertEq(vault.convertToAssets(vault.balanceOf(bob)), 27553);
    }

    function bobWithdrawsTokens(uint256 initAliceBalance, uint256 initBobBalance, uint256 tolerance) internal {
        // 11. Bob withdraws 200 assets (189 shares)
        // shares  = assets / token price exchange
        // shares  = 200 / 1.061747346723 = 188.36873067522544833543855249107251034179140300190099616187369285 and up 189
        vm.prank(bob);
        vault.withdraw(200, bob, bob);

        assertEq(underlying.balanceOf(bob), 200 + initAliceBalance);
        uint256 zero = 0;
        assertEq(vault.totalSupply(), zero + 23010 + 2667 + 2000 + 941 - 189);
        // bob shares =  23010 + 2000 + 941 - 189 = 25762
        // alice shares = 4000 - 1333 = 2667
        // total assets = (bob shares + alice shares) * token exchange price = (25762 + 2667) * 1.061747346723  = 30184.415319988167 and down = 30184
        assertEq(vault.totalAssets(), 30184);
        // balance for alice should stay the same
        assertEq(vault.balanceOf(alice), 2667);
        // assets = 2667 * 1.061747346723 = 2831.680173710241 and down 2831
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), 2831);
        // bob redeemed 189 shares in this part
        assertEq(vault.balanceOf(bob), 23010 + 2000 + 941 - 189);
        // bob shares =  23010 + 2000 + 941 - 189 = 25762
        // assets = 25762 * 1.061747346723 = 27352.735146277926 and down 27352
        assertEq(vault.convertToAssets(vault.balanceOf(bob)), 27352);
    }

    function aliceWithdrawsTokens(uint256 initAliceBalance, uint256 initBobBalance, uint256 tolerance) internal {
        // 13. Alice withdraws 1000 assets (902 shares)
        // shares  = assets / token price exchange
        // shares  = 1000 / 1.109437570931 = 901.35761236284441213775719917232300648568020006915011336385628662 and up 902
        vm.prank(alice);
        vault.withdraw(1000, alice, alice);

        assertEq(underlying.balanceOf(alice), 1415 + 1000 + initAliceBalance);
        assertEq(vault.totalSupply(), 23010 + 2667 + 2000 + 941 - 189 - 902);
        // bob shares =  23010 + 2000 + 941 - 189 = 25762
        // alice shares = 4000 - 1333 - 902 = 1765
        // total assets = (bob shares + alice shares) * token exchange price = (25762 + 1765) *  1.109437570931  = 30539.488015017637 and down = 30539
        assertEq(vault.totalAssets(), 30539);
        // alice shares = 4000 - 1333 - 902 = 1765
        assertEq(vault.balanceOf(alice), 1765);
        // alice shares = 4000 - 1333 - 902 = 1765
        // alice assets = shares * token exchange price
        // alice assets = 1765 *  1.109437570931 = 1958.157312693215 and down 1958
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), 1958);

        // bob shares =  23010 + 2000 + 941 - 189 = 25762
        uint256 zero = 0;
        assertEq(vault.balanceOf(bob), zero + 25762);
        // bob shares =  23010 + 2000 + 941 - 189 = 25762
        // bob assets = shares * token exchange price
        // bob assets = 25762 *  1.109437570931 = 28581.330702324422 and down
        assertEq(vault.convertToAssets(vault.balanceOf(bob)), 28581);
    }

    function bobRedeemsShares(uint256 initAliceBalance, uint256 initBobBalance, uint256 tolerance) internal {
        // 14. Bob redeem 3071 shares (3407 tokens)
        vm.prank(bob);
        vault.redeem(3071, bob, bob);

        // assets = shares * token exchange price
        // assets = 3071 *  1.109437570931  = 3407.082780329101 and down = 3407
        assertEq(underlying.balanceOf(bob), 200 + 3407 + initAliceBalance);
        uint256 zero = 0;
        // bob redeemed 3071 shares
        assertEq(vault.totalSupply(), zero + 23010 + 2667 + 2000 + 941 - 189 - 902 - 3071);
        // total assets = (bob shares + alice shares) * token exchange price = 24456 *  1.109437570931 = 27132.405234688536 and down = 27132
        assertEq(vault.totalAssets(), 27132);
        // balance for alice should stay the same

        // alice shares = 4000 - 1333 - 902 = 1765
        assertEq(vault.balanceOf(alice), 1765);
        // alice shares = 4000 - 1333 - 902 = 1765
        // assets = shares * token exchange price = 1765 * 1.109437570931 = 1958.157312693215 and down 1958
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), 1958);
        // bob redeemed 189 shares in this part
        assertEq(vault.balanceOf(bob), 23010 + 2000 + 941 - 189 - 3071);
        // bob shares =  23010 + 2000 + 941 - 189 - 3071 = 22691
        // assets = 22691 *  1.109437570931 = 25174.247921995321 and down 25174
        assertEq(vault.convertToAssets(vault.balanceOf(bob)), 25174);
        // Sanity check
        assertEq(underlying.balanceOf(address(vault)), 3000);
    }

    function testWithdrawZero() public virtual override {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__OperateAmountsZero)
        );
        super.testWithdrawZero();
    }
}

contract ERC4626iTokenCustomCasesTest is ERC4626iTokenHelperTest {
    address john = address(0x123F);

    // ========= TEST FOR ERC4626 STANDARD TESTS FROM SOLMATE

    function setUp() public virtual override {
        super.setUp();
        vm.prank(admin);
        IIToken(address(token)).updateRebalancer(admin);
    }

    //  if lendingRewardsRateModel says rewards are active and distributes rewards but admin did not fund enough rewards via "rebalance".
    // Liquidity balance would simply be insufficient if all users would want to withdraw so would revert.
    // But can once verify this with a test and verify that once admin funds rewards all users can withdraw normally.
    function test_AllUsersWantToWithdrawRewardsActiveButInsufficientLiquidityBalance() public {
        vm.prank(alice);
        asset.burn(address(liquidity), asset.balanceOf(address(liquidity)));
        (rateModel, endTime_, startTime_) = activateRewardRateModel();

        assertEq(asset.balanceOf(address(liquidity)), 0);

        uint256 fundAmount = 2000;
        vm.prank(alice);
        asset.mint(alice, fundAmount);
        vm.prank(alice);
        token.deposit(fundAmount, alice);
        vm.prank(bob);
        asset.mint(bob, fundAmount);
        vm.prank(bob);
        asset.approve(address(token), type(uint256).max);
        vm.prank(bob);
        token.deposit(fundAmount, bob);

        vm.warp(block.timestamp + (PASS_1YEAR_TIME * 3) / 4);

        uint256 aliceSharesConvertedToAssets = token.convertToAssets(token.balanceOf(alice));
        vm.prank(alice);
        token.withdraw(aliceSharesConvertedToAssets - 10, alice, alice); //alice withraws ALMOST all assets (alice and bob deposited assets) from token

        uint256 aliceAndBobAssetsAfterAliceWithdraw = token.convertToAssets(token.balanceOf(alice)) +
            token.convertToAssets(token.balanceOf(bob)); // rest of the assets

        //bob
        uint256 bobSharesConvertedToAssets = token.convertToAssets(token.balanceOf(bob));
        // should revert because there is no enough assets in liquidity
        vm.expectRevert();
        vm.prank(bob);
        token.withdraw(bobSharesConvertedToAssets, bob, bob);

        asset.mint(admin, aliceAndBobAssetsAfterAliceWithdraw);
        _setApproval(IERC20(address(asset)), address(token), admin);
        vm.prank(admin);
        IIToken(address(token)).rebalance();

        //now bob can withdraw rest of his  assets
        uint256 restBobBalance = token.convertToAssets(token.balanceOf(bob));
        vm.prank(bob);
        token.withdraw(restBobBalance, bob, bob);

        //alice as well
        uint256 restAliceBalance = token.convertToAssets(token.balanceOf(alice));
        vm.prank(alice);
        token.withdraw(restAliceBalance, alice, alice);

        assertEq(token.totalSupply(), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    // Special case of all depositors fully withdraw and then deposits start again. Does yield accrue as expected for new depositors? We can assume liquidity balance is present thanks to initial initialDeposit call.
    function test_DepositorsFullyWithdrawAndStartAgain() public {
        // A = Alice, B = Bob, B = Jon
        //  _______________________________________________________________________________________
        // | Vault shares | A share | A assets | B share | B assets  | C share | C assets |       |
        // |======================================================================================|
        // | 0. Initial state after initial deposit                                               |
        // |------------|-----------|-----------|-----------|-------------|-----------|-----------|
        // |      30000 |         0 |         0 |         0 |           0 |         0 |         0 |
        // |------------|-----------|-----------|-----------|-------------|-----------|-----------|
        // | 1. Warp time to 10% of whole period (exchange token price goes up because of rewards)|
        // |------------|-----------|-----------|-----------|-------------|-----------|-----------|
        // | 2. All deposit 2000 tokens (1990 shares)                     |           |           |
        // |------------|-----------|-----------|-----------|-------------|-----------|-----------|
        // |      35970 |      1990 |    2000   |      1990 |        2000 |      1990 |      2000 |
        // |------------|-----------|-----------|-----------|-------------|-----------|-----------|
        // | 3. All users withdraw                                                                |
        // |------------|-----------|-----------|-----------|-------------|-----------|-----------|
        // |      30000 |         0 |        0  |         0 |           0 |         0 |         0 |
        // |------------|-----------|-----------|-----------|-------------|-----------|-----------|
        // | 4. Warp time to 75% of the whole period                                              |
        // |------------|-----------|-----------|-----------|-------------|-----------|-----------|
        // | 5. Deactivate rewards                                                                |
        // |------------|-----------|-----------|-----------|-------------|-----------|-----------|
        // | 6. Warp time to 80% of the whole period                                              |
        // |------------|-----------|-----------|-----------|-------------|-----------|-----------|
        // | 7. Activate rewards                                                                  |
        // |------------|-----------|-----------|-----------|-------------|-----------|-----------|
        // | 8. Warp time to 90% of the whole period                                              |
        // |------------|-----------|-----------|-----------|-------------|-----------|-----------|
        // | 9. All deposits 2000 tokens                                                          |
        // |------------|-----------|-----------|-----------|-------------|-----------|-----------|
        // |      35751 |      1917 |     2000  |      1917 |        2000 |      1917 |      2000 |
        // |------------|-----------|-----------|-----------|-------------|-----------|-----------|
        // | 10. Warp time to 100% of the whole period                                            |
        // |------------|-----------|-----------|-----------|-------------|-----------|-----------|
        // |      35751 |      1917 |     2008  |      1917 |        2008 |      1917 |      2008 |
        // |------------|-----------|-----------|-----------|-------------|-----------|-----------|
        // | 9. All users withdraw                                                                |
        // |------------|-----------|-----------|-----------|-------------|-----------|-----------|
        // |      30000 |         0 |        0  |         0 |           0 |         0 |         0 |
        // |------------|-----------|-----------|-----------|-------------|-----------|-----------|

        (rateModel, endTime_, startTime_) = activateRewardRateModel();
        initialDeposit();

        assertEq(block.timestamp, 3153601);
        // 1. Warp time to 10% of whole period (exchange token price goes up because of rewards)
        vm.warp(block.timestamp + (PASS_1YEAR_TIME) / 10);
        assertEq(block.timestamp, 6307201); // 3153601 + (31536000 * 1 / 10) = 6307201

        // 2. All deposit 2000 tokens (costs 1990 tokens)
        // all deposit 2000 assets (1990 shares)
        depositForUsers(alice, bob, john);
        assertsAfterFirstDeposit(IIToken(address(token)));
        // 3. All users withdraw
        withdrawForUsers(alice, bob, john, IIToken(address(token)));
        // 4. Warp time to 75% of the whole period
        vm.warp(block.timestamp + (((PASS_1YEAR_TIME) * 65) / 100));
        assertEq(block.timestamp, 26805601); // 3153601 + (31536000 * 3 / 4) = 26805601
        assertsAfterSecondWarp(IIToken(address(token)));

        // 5. Deactivate rewards
        deactivateRewards(IIToken(address(token)));

        // 6. Warp time to 80% of the whole period
        vm.warp(block.timestamp + (((PASS_1YEAR_TIME) * 5) / 100));
        assertEq(block.timestamp, 28382401); // 3153601 + (31536000 * 4 / 5) = 28382401
        assertsAfterThirdWarp(IIToken(address(token)));

        // 7. Activate rewards
        activateRewards(IIToken(address(token)));

        // 8. Warp time to 90% of the whole period
        vm.warp(block.timestamp + (((PASS_1YEAR_TIME) * 1) / 10));
        assertEq(block.timestamp, 31536001); // 3153601 + (31536000 * 9 / 10) = 31536001
        assertsAfterFourthWarp(IIToken(address(token)));

        // 9. All deposits 2000 tokens
        secondRoundOfDeposits(alice, bob, john);
        // 10. Warp time to 100% of the whole period
        vm.warp(block.timestamp + (((PASS_1YEAR_TIME) * 1) / 10));

        assertEq(block.timestamp, 34689601); // 3153601 + 31536000 = 34689601
        assertsAfterFinalWarp(IIToken(address(token)));
        // 9. All users withdraw
        finalWithdrawForUsers(alice, bob, john, IIToken(address(token)));
    }

    function initialDeposit() private {
        uint256 assetsAmount = 30_000;
        asset.mint(admin, assetsAmount);
        vm.prank(admin);
        asset.approve(address(token), assetsAmount);
        vm.prank(admin);
        IIToken(address(token)).deposit(assetsAmount, admin);
    }

    function depositForUsers(address alice, address bob, address john) private {
        uint256 fundAmount = 2000;
        // shares = assets / token exchnage price
        // shares = 2000 / 1.005 = 1990.0497512437810945273631840796019900497512437810945273631840796 and down = 1990
        // will mint 1990 shares
        // Alice's deposit
        makeDeposit(alice, fundAmount);
        // Bob's deposit
        makeDeposit(bob, fundAmount);
        // John's deposit
        makeDeposit(john, fundAmount);
    }

    function assertsAfterFirstDeposit(IIToken token) private {
        (, , , , , , , , uint256 tokenExchangePrice) = token.getData();
        // rewards return in percentage = rewardsRate * timeElapsed / SECONDS_PER_YEAR
        // rewards return in percentage = 5000000000000 * (6307201 - 3153601) / 31536000 (rewardRate proper calculation confirmed in lendingRewardsRateModel.t.sol)
        // rewards return in percentage = 5000000000000 * 3153600 / 31536000
        // rewards return in percentage = 500000000000

        // token exchange price_ = oldTokenExchangePrice_ + oldTokenExchangePrice_ * totalReturnInPercent_ / 1e14
        // token exchange price_ = 1 + 1 * 500000000000 / 1e14
        // token exchange price_ = 1.005
        assertEq(tokenExchangePrice, 1005000000000);

        // each has 1990 shares
        assertEq(token.balanceOf(alice), 1990);
        assertEq(token.balanceOf(bob), 1990);
        assertEq(token.balanceOf(john), 1990);

        // 1990 * 1.005 = 1999.95 and down 1999
        assertEq(token.convertToAssets(token.balanceOf(alice)), 1999);
        assertEq(token.convertToAssets(token.balanceOf(bob)), 1999);
        assertEq(token.convertToAssets(token.balanceOf(john)), 1999);
    }

    function withdrawForUsers(address alice, address bob, address john, IIToken token) private {
        // Alice's withdrawal
        makeWithdrawal(alice, token);
        // Bob's withdrawal
        makeWithdrawal(bob, token);
        // John's withdrawal
        makeWithdrawal(john, token);
    }

    function assertsAfterSecondWarp(IIToken token) private {
        (, , , , , , , , uint256 tokenExchangePrice) = token.getData();

        // rewards return in percentage = rewardsRate * timeElapsed / SECONDS_PER_YEAR
        // rewards return in percentage = 4998593750000 * (26805601 - 6307201) / 31536000 (rewardRate proper calculation confirmed in lendingRewardsRateModel.t.sol)
        // rewards return in percentage = 4998593750000 * 20498400 / 31536000
        // rewards return in percentage = 3249085937500

        // token exchange price_ = oldTokenExchangePrice_ + oldTokenExchangePrice_ * totalReturnInPercent_ / 1e14
        // token exchange price_ = 1.005 + 1.005 * 3249085937500 / 1e14
        // token exchange price_ = 1,037653313671

        assertEq(tokenExchangePrice, 1037653313671);

        // all have 0 shares
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(john), 0);
    }

    function deactivateRewards(IIToken token) private {
        vm.prank(admin);
        token.updateRewards(ILendingRewardsRateModel(address(0)));
    }

    function assertsAfterThirdWarp(IIToken token) private {
        (, , , , , , , , uint256 tokenExchangePrice) = token.getData();

        // rewards return in percentage = 0 is because rewards are not active

        // token exchange price_ = oldTokenExchangePrice_ + oldTokenExchangePrice_ * totalReturnInPercent_ / 1e12
        // token exchange price_ = 1.037653313671 + 1.037653313671  * 0 / 1e12
        // token exchange price_ = 1.037653313671

        assertEq(tokenExchangePrice, 1037653313671);

        // all have 0 shares
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(john), 0);
    }

    function activateRewards(IIToken token) private {
        vm.prank(admin);
        token.updateRewards(ILendingRewardsRateModel(address(rateModel)));
    }

    function assertsAfterFourthWarp(IIToken token) private {
        (, , , , , , , , uint256 tokenExchangePrice) = token.getData();

        // rewards return in percentage = rewardsRate * timeElapsed / SECONDS_PER_YEAR
        // rewards return in percentage = 4989415625000 * (31536001 - 28382401) / 31536000 (rewardRate proper calculation confirmed in lendingRewardsRateModel.t.sol)
        // rewards return in percentage = 4989415625000 * 3153600 / 31536000
        // rewards return in percentage = 498941562500

        // token exchange price_ = oldTokenExchangePrice_ + oldTokenExchangePrice_ * totalReturnInPercent_ / 1e14
        // token exchange price_ = 1.037653313671 + 1.037653313671  * 498941562500 / 1e14
        // token exchange price_ = 1.042830597327563113509375

        assertEq(tokenExchangePrice, 1042830597327);
    }

    function secondRoundOfDeposits(address alice, address bob, address john) private {
        uint256 fundAmount = 2000;

        //  shares = assets / token exchange price
        //  shares = 2000 / 1.042830597327563113509375
        //  shares = 1917.8570374952095671318349351508251670353168240178851126716738227 and down 1917

        // Alice's second deposit
        makeDeposit(alice, fundAmount);
        // Bob's second deposit
        makeDeposit(bob, fundAmount);
        // John's second deposit
        makeDeposit(john, fundAmount);
    }

    function assertsAfterFinalWarp(IIToken token) private {
        (, , , , , , , , uint256 tokenExchangePrice) = token.getData();

        // rewards return in percentage = rewardsRate * timeElapsed / SECONDS_PER_YEAR
        // rewards return in percentage = 4931731250000 * (34689601 - 31536001) / 31536000 (rewardRate proper calculation confirmed in lendingRewardsRateModel.t.sol)
        // rewards return in percentage = 4931731250000 * 3153600 / 31536000
        // rewards return in percentage = 493173125000

        // token exchange price_ = oldTokenExchangePrice_ + oldTokenExchangePrice_ * totalReturnInPercent_ / 1e14
        // token exchange price_ = 1.042830597327563113509375 + 1.042830597327563113509375 * 493173125000 / 1e14
        // token exchange price_ = 1.04797355757285962300261648185546875

        assertEq(tokenExchangePrice, 1047973557572);

        // each has 1917 shares
        assertEq(token.balanceOf(alice), 1917);
        assertEq(token.balanceOf(bob), 1917);
        assertEq(token.balanceOf(john), 1917);

        // 1917 * 1.047973557572 = 2008.965309865524
        assertEq(token.convertToAssets(token.balanceOf(alice)), 2008);
        assertEq(token.convertToAssets(token.balanceOf(bob)), 2008);
        assertEq(token.convertToAssets(token.balanceOf(john)), 2008);
    }

    function finalWithdrawForUsers(address alice, address bob, address john, IIToken token) private {
        // Alice's final withdrawal
        makeWithdrawal(alice, token);
        // Bob's final withdrawal
        makeWithdrawal(bob, token);
        // John's final withdrawal
        makeWithdrawal(john, token);

        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(john), 0);
    }

    // Helper functions for deposit and withdrawal
    function makeDeposit(address user, uint256 amount) private {
        vm.prank(user);
        asset.mint(user, amount);
        vm.prank(user);
        asset.approve(address(token), amount);
        vm.prank(user);
        token.deposit(amount, user);
    }

    function makeWithdrawal(address user, IIToken token) private {
        uint256 userBalance = token.convertToAssets(token.balanceOf(user));
        vm.prank(user);
        token.withdraw(userBalance, user, user);
    }
}

contract ERC4626iToken_Invariants_Handler_Test is ERC4626iTokenHelperTest {
    Handler handler;
    address john = address(0xABFF);

    address[] users = new address[](3);
    uint256 lastTokenExchangePrice;

    function setUp() public virtual override(ERC4626iTokenHelperTest) {
        ERC4626iTokenHelperTest.setUp();
        (rateModel, endTime_, startTime_) = activateRewardRateModel();
        users[0] = address(alice);
        users[1] = address(bob);
        users[2] = address(john);
        handler = new Handler(IIToken(address(token)), address(asset), users, admin);

        vm.prank(alice);
        asset.approve(address(token), type(uint256).max);

        vm.prank(bob);
        asset.approve(address(token), type(uint256).max);

        vm.prank(john);
        asset.approve(address(token), type(uint256).max);

        vm.prank(alice);
        asset.approve(address(handler), type(uint256).max);

        vm.prank(bob);
        asset.approve(address(handler), type(uint256).max);

        vm.prank(john);
        asset.approve(address(handler), type(uint256).max);

        vm.prank(alice);
        token.approve(address(handler), type(uint256).max);

        vm.prank(bob);
        token.approve(address(handler), type(uint256).max);

        vm.prank(john);
        token.approve(address(handler), type(uint256).max);

        targetContract(address(handler));

        // address[] memory senders = [alice, bob];
        targetSender(alice);
        targetSender(bob);

        vm.prank(admin);
        factory.setAuth(alice, true);
        vm.prank(admin);
        factory.setAuth(bob, true);
        vm.prank(admin);
        factory.setAuth(john, true);

        (, , , , , , , , lastTokenExchangePrice) = IIToken(address(token)).getData();

        asset.mint(bob, 5e18);
        vm.prank(bob);
        token.deposit(5e18, bob);

        asset.mint(alice, 5e18);
        vm.prank(alice);
        token.deposit(5e18, alice);

        asset.mint(john, 5e18);
        vm.prank(john);
        token.deposit(5e18, john);
    }

    function invariant_TokenExchangePriceShouldOnlyGoUp() public {
        // exchange price should only ever go up
        (, , , , , , , , uint256 currentTokenExchangePrice) = IIToken(address(token)).getData();
        assertGe(currentTokenExchangePrice, lastTokenExchangePrice, "Token exchange price should not decrease");
    }

    function invariant_UndelyingBalanceOfITokenShouldNeverBeGreaterThanZero() public {
        // with normal interactions (supply, withdraw) ERC20 underlying balanceOf iToken should never be > 0.
        assertEq(asset.balanceOf(address(token)), 0, "Token exchange price should not decrease");
    }

    function invariant_SharesShouldAlwaysBeSumOfAllDepositorsShares() public {
        // shares should always be sum of all depositors shares

        uint256 sum;
        for (uint256 i = 0; i > users.length; i++) {
            sum += IIToken(address(token)).balanceOf(users[i]);
        }
        assertGe(IIToken(address(token)).totalAssets(), sum, "Token exchange price should not decrease");
    }

    function invariant_Metadata() public {
        assertEq(token.name(), string.concat("Fluid Interest ", asset.symbol()));
        assertEq(token.symbol(), string.concat("fi", asset.symbol()));
        assertEq(token.decimals(), token.decimals());
    }
}
