// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IVaultT1 } from "../../../protocols/vault/interfaces/iVaultT1.sol";
import { Structs as LiquidityResolverStructs } from "../liquidity/structs.sol";

contract Structs {
    struct Configs {
        uint16 supplyRateMagnifier;
        uint16 borrowRateMagnifier;
        uint16 collateralFactor;
        uint16 liquidationThreshold;
        uint16 liquidationMaxLimit;
        uint16 withdrawalGap;
        uint16 liquidationPenalty;
        uint16 borrowFee;
        address oracle;
        uint oraclePrice;
        address rebalancer;
    }

    struct ExchangePricesAndRates {
        uint lastStoredLiquiditySupplyExchangePrice;
        uint lastStoredLiquidityBorrowExchangePrice;
        uint lastStoredVaultSupplyExchangePrice;
        uint lastStoredVaultBorrowExchangePrice;
        uint liquiditySupplyExchangePrice;
        uint liquidityBorrowExchangePrice;
        uint vaultSupplyExchangePrice;
        uint vaultBorrowExchangePrice;
        uint supplyRateVault;
        uint borrowRateVault;
        uint supplyRateLiquidity;
        uint borrowRateLiquidity;
    }

    struct TotalSupplyAndBorrow {
        uint totalSupplyVault;
        uint totalBorrowVault;
        uint totalSupplyLiquidity;
        uint totalBorrowLiquidity;
        uint absorbedSupply;
        uint absorbedBorrow;
    }

    struct LimitsAndAvailability {
        uint withdrawLimit;
        uint withdrawableUntilLimit;
        uint withdrawable;
        uint borrowLimit;
        uint borrowableUntilLimit;
        uint borrowable;
        uint minimumBorrowing;
    }

    struct CurrentBranchState {
        uint status; // if 0 then not liquidated, if 1 then liquidated, if 2 then merged, if 3 then closed
        int minimaTick;
        uint debtFactor;
        uint partials;
        uint debtLiquidity;
        uint baseBranchId;
        int baseBranchMinima;
    }

    struct VaultState {
        uint totalPositions;
        int topTick;
        uint currentBranch;
        uint totalBranch;
        uint totalBorrow;
        uint totalSupply;
        CurrentBranchState currentBranchState;
    }

    struct VaultEntireData {
        address vault;
        IVaultT1.ConstantViews constantVariables;
        Configs configs;
        ExchangePricesAndRates exchangePricesAndRates;
        TotalSupplyAndBorrow totalSupplyAndBorrow;
        LimitsAndAvailability limitsAndAvailability;
        VaultState vaultState;
        // liquidity related data such as supply amount, limits, expansion etc.
        LiquidityResolverStructs.UserSupplyData liquidityUserSupplyData;
        // liquidity related data such as borrow amount, limits, expansion etc.
        LiquidityResolverStructs.UserBorrowData liquidityUserBorrowData;
    }

    struct UserPosition {
        uint nftId;
        address owner;
        bool isLiquidated;
        bool isSupplyPosition; // if true that means borrowing is 0
        int tick;
        uint tickId;
        uint beforeSupply;
        uint beforeBorrow;
        uint beforeDustBorrow;
        uint supply;
        uint borrow;
        uint dustBorrow;
    }

    /// @dev liquidation related data
    /// @param vault address of vault
    /// @param tokenIn_ address of token in
    /// @param tokenOut_ address of token out
    /// @param tokenInAmtOne_ (without absorb liquidity) minimum of available liquidation & tokenInAmt_
    /// @param tokenOutAmtOne_ (without absorb liquidity) expected token out, collateral to withdraw
    /// @param tokenInAmtTwo_ (absorb liquidity included) minimum of available liquidation & tokenInAmt_. In most cases it'll be same as tokenInAmtOne_ but sometimes can be bigger.
    /// @param tokenOutAmtTwo_ (absorb liquidity included) expected token out, collateral to withdraw. In most cases it'll be same as tokenOutAmtOne_ but sometimes can be bigger.
    /// @dev sometimes Liquidity in Two will always be >= One. Sometimes One can provide better swaps, sometimes Two can provide better swaps. But as mentioned availability in Two will always be >= One
    struct LiquidationStruct {
        address vault;
        address tokenIn;
        address tokenOut;
        uint tokenInAmtOne;
        uint tokenOutAmtOne;
        uint tokenInAmtTwo;
        uint tokenOutAmtTwo;
    }
}
