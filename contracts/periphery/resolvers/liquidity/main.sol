// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { LiquidityCalcs } from "../../../libraries/liquidityCalcs.sol";
import { BigMathMinified } from "../../../libraries/bigMathMinified.sol";
import { LiquiditySlotsLink } from "../../../libraries/liquiditySlotsLink.sol";
import { ILiquidity } from "../../../liquidity/interfaces/iLiquidity.sol";
import { ILiquidityResolver } from "./iLiquidityResolver.sol";
import { Structs } from "./structs.sol";
import { Variables } from "./variables.sol";

interface TokenInterface {
    function balanceOf(address) external view returns (uint);
}

/// @notice Fluid Liquidity resolver
/// Implements various view-only methods to give easy access to Liquidity data.
contract LiquidityResolver is ILiquidityResolver, Variables, Structs {
    /// @dev address that is mapped to the chain native token
    address internal constant _NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice thrown if an input param address is zero
    error LiquidityResolver__AddressZero();

    constructor(ILiquidity liquidity_) Variables(liquidity_) {
        if (address(liquidity_) == address(0)) {
            revert LiquidityResolver__AddressZero();
        }
    }

    /// @inheritdoc ILiquidityResolver
    function getRevenueCollector() public view returns (address) {
        return address(uint160(LIQUIDITY.readFromStorage(bytes32(0))));
    }

    /// @inheritdoc ILiquidityResolver
    function getRevenue(address token_) public view returns (uint256 revenueAmount_) {
        uint256 liquidityTokenBalance_ = token_ == _NATIVE_TOKEN_ADDRESS
            ? address(LIQUIDITY).balance
            : IERC20(token_).balanceOf(address(LIQUIDITY));

        return
            LiquidityCalcs.calcRevenue(
                getTotalAmounts(token_),
                getExchangePricesAndConfig(token_),
                liquidityTokenBalance_
            );
    }

    /// @inheritdoc ILiquidityResolver
    function getStatus() public view returns (uint256) {
        return LIQUIDITY.readFromStorage(bytes32(LiquiditySlotsLink.LIQUIDITY_STATUS_SLOT));
    }

    /// @inheritdoc ILiquidityResolver
    function isAuth(address auth_) public view returns (uint256) {
        return
            LIQUIDITY.readFromStorage(
                LiquiditySlotsLink.calculateMappingStorageSlot(LiquiditySlotsLink.LIQUIDITY_AUTHS_MAPPING_SLOT, auth_)
            );
    }

    /// @inheritdoc ILiquidityResolver
    function isGuardian(address guardian_) public view returns (uint256) {
        return
            LIQUIDITY.readFromStorage(
                LiquiditySlotsLink.calculateMappingStorageSlot(
                    LiquiditySlotsLink.LIQUIDITY_GUARDIANS_MAPPING_SLOT,
                    guardian_
                )
            );
    }

    /// @inheritdoc ILiquidityResolver
    function getUserClass(address user_) public view returns (uint256) {
        return
            LIQUIDITY.readFromStorage(
                LiquiditySlotsLink.calculateMappingStorageSlot(
                    LiquiditySlotsLink.LIQUIDITY_USER_CLASS_MAPPING_SLOT,
                    user_
                )
            );
    }

    /// @inheritdoc ILiquidityResolver
    function getExchangePricesAndConfig(address token_) public view returns (uint256) {
        return
            LIQUIDITY.readFromStorage(
                LiquiditySlotsLink.calculateMappingStorageSlot(
                    LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT,
                    token_
                )
            );
    }

    /// @inheritdoc ILiquidityResolver
    function getRateConfig(address token_) public view returns (uint256) {
        return
            LIQUIDITY.readFromStorage(
                LiquiditySlotsLink.calculateMappingStorageSlot(
                    LiquiditySlotsLink.LIQUIDITY_RATE_DATA_MAPPING_SLOT,
                    token_
                )
            );
    }

    /// @inheritdoc ILiquidityResolver
    function getTotalAmounts(address token_) public view returns (uint256) {
        return
            LIQUIDITY.readFromStorage(
                LiquiditySlotsLink.calculateMappingStorageSlot(
                    LiquiditySlotsLink.LIQUIDITY_TOTAL_AMOUNTS_MAPPING_SLOT,
                    token_
                )
            );
    }

    /// @inheritdoc ILiquidityResolver
    function getUserSupply(address user_, address token_) public view returns (uint256) {
        return
            LIQUIDITY.readFromStorage(
                LiquiditySlotsLink.calculateDoubleMappingStorageSlot(
                    LiquiditySlotsLink.LIQUIDITY_USER_SUPPLY_DOUBLE_MAPPING_SLOT,
                    user_,
                    token_
                )
            );
    }

    /// @inheritdoc ILiquidityResolver
    function getUserBorrow(address user_, address token_) public view returns (uint256) {
        return
            LIQUIDITY.readFromStorage(
                LiquiditySlotsLink.calculateDoubleMappingStorageSlot(
                    LiquiditySlotsLink.LIQUIDITY_USER_BORROW_DOUBLE_MAPPING_SLOT,
                    user_,
                    token_
                )
            );
    }

    /// @inheritdoc ILiquidityResolver
    function getTokenRateData(address token_) public view returns (RateData memory rateData_) {
        uint256 rateConfig_ = getRateConfig(token_);

        rateData_.version = rateConfig_ & 0xF;

        if (rateData_.version == 1) {
            rateData_.rateDataV1.rateAtUtilizationZero =
                (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V1_RATE_AT_UTILIZATION_ZERO) &
                X16;
            rateData_.rateDataV1.kink = (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V1_UTILIZATION_AT_KINK) & X16;
            rateData_.rateDataV1.rateAtUtilizationKink =
                (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V1_RATE_AT_UTILIZATION_KINK) &
                X16;
            rateData_.rateDataV1.rateAtUtilizationMax =
                (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V1_RATE_AT_UTILIZATION_MAX) &
                X16;
        } else if (rateData_.version == 2) {
            rateData_.rateDataV2.rateAtUtilizationZero =
                (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V2_RATE_AT_UTILIZATION_ZERO) &
                X16;
            rateData_.rateDataV2.kink1 =
                (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V2_UTILIZATION_AT_KINK1) &
                X16;
            rateData_.rateDataV2.rateAtUtilizationKink1 =
                (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V2_RATE_AT_UTILIZATION_KINK1) &
                X16;
            rateData_.rateDataV2.kink2 =
                (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V2_UTILIZATION_AT_KINK2) &
                X16;
            rateData_.rateDataV2.rateAtUtilizationKink2 =
                (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V2_RATE_AT_UTILIZATION_KINK2) &
                X16;
            rateData_.rateDataV2.rateAtUtilizationMax =
                (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V2_RATE_AT_UTILIZATION_MAX) &
                X16;
        } else {
            revert("not-valid-rate-version");
        }
    }

    /// @inheritdoc ILiquidityResolver
    function getTokensRateData(address[] calldata tokens_) public view returns (RateData[] memory rateDatas_) {
        uint256 length_ = tokens_.length;
        rateDatas_ = new RateData[](length_);

        for (uint256 i; i < length_; i++) {
            rateDatas_[i] = getTokenRateData(tokens_[i]);
        }
    }

    /// @inheritdoc ILiquidityResolver
    function getOverallTokenData(
        address token_
    ) public view returns (Structs.OverallTokenData memory overallTokenData_) {
        uint256 exchangePriceAndConfig_ = getExchangePricesAndConfig(token_);
        uint256 totalAmounts_ = getTotalAmounts(token_);

        (overallTokenData_.supplyExchangePrice, overallTokenData_.borrowExchangePrice) = LiquidityCalcs
            .calcExchangePrices(exchangePriceAndConfig_);

        overallTokenData_.borrowRate = exchangePriceAndConfig_ & X16;
        overallTokenData_.fee = (exchangePriceAndConfig_ >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_FEE) & X14;
        overallTokenData_.lastStoredUtilization =
            (exchangePriceAndConfig_ >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_UTILIZATION) &
            X14;
        overallTokenData_.storageUpdateThreshold =
            (exchangePriceAndConfig_ >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_UPDATE_THRESHOLD) &
            X14;
        overallTokenData_.lastUpdateTimestamp =
            (exchangePriceAndConfig_ >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_LAST_TIMESTAMP) &
            X33;

        // Extract supply & borrow amounts
        uint256 temp_ = totalAmounts_ & X64;
        overallTokenData_.supplyRawInterest = (temp_ >> DEFAULT_EXPONENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK);
        temp_ = (totalAmounts_ >> LiquiditySlotsLink.BITS_TOTAL_AMOUNTS_SUPPLY_INTEREST_FREE) & X64;
        overallTokenData_.supplyInterestFree = (temp_ >> DEFAULT_EXPONENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK);
        temp_ = (totalAmounts_ >> LiquiditySlotsLink.BITS_TOTAL_AMOUNTS_BORROW_WITH_INTEREST) & X64;
        overallTokenData_.borrowRawInterest = (temp_ >> DEFAULT_EXPONENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK);
        // no & mask needed for borrow interest free as it occupies the last bits in the storage slot
        temp_ = (totalAmounts_ >> LiquiditySlotsLink.BITS_TOTAL_AMOUNTS_BORROW_INTEREST_FREE);
        overallTokenData_.borrowInterestFree = (temp_ >> DEFAULT_EXPONENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK);

        uint256 supplyWithInterest_ = (overallTokenData_.supplyRawInterest * overallTokenData_.supplyExchangePrice) /
            EXCHANGE_PRICES_PRECISION; // normalized from raw
        overallTokenData_.totalSupply = supplyWithInterest_ + overallTokenData_.supplyInterestFree;
        uint256 borrowWithInterest_ = (overallTokenData_.borrowRawInterest * overallTokenData_.borrowExchangePrice) /
            EXCHANGE_PRICES_PRECISION; // normalized from raw
        overallTokenData_.totalBorrow = borrowWithInterest_ + overallTokenData_.borrowInterestFree;

        if (supplyWithInterest_ > 0) {
            overallTokenData_.supplyRate =
                (overallTokenData_.borrowRate * (FOUR_DECIMALS - overallTokenData_.fee) * borrowWithInterest_) /
                (supplyWithInterest_ * FOUR_DECIMALS);
        }

        overallTokenData_.revenue = getRevenue(token_);
        overallTokenData_.rateData = getTokenRateData(token_);
    }

    /// @inheritdoc ILiquidityResolver
    function getOverallTokensData(
        address[] calldata tokens_
    ) public view returns (Structs.OverallTokenData[] memory overallTokensData_) {
        uint256 length_ = tokens_.length;
        overallTokensData_ = new Structs.OverallTokenData[](length_);
        for (uint256 i; i < length_; i++) {
            overallTokensData_[i] = getOverallTokenData(tokens_[i]);
        }
    }

    /// @inheritdoc ILiquidityResolver
    function getUserSupplyData(
        address user_,
        address token_
    )
        public
        view
        returns (Structs.UserSupplyData memory userSupplyData_, Structs.OverallTokenData memory overallTokenData_)
    {
        overallTokenData_ = getOverallTokenData(token_);
        uint256 userSupply_ = getUserSupply(user_, token_);

        userSupplyData_.modeWithInterest = userSupply_ & 1 == 1;
        userSupplyData_.supply = BigMathMinified.fromBigNumber(
            (userSupply_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_AMOUNT) & X64,
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK
        );

        // get updated expanded withdrawal limit
        userSupplyData_.withdrawalLimit = LiquidityCalcs.calcWithdrawalLimitBeforeOperate(
            userSupply_,
            userSupplyData_.supply
        );

        userSupplyData_.lastUpdateTimestamp =
            (userSupply_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_LAST_UPDATE_TIMESTAMP) &
            X33;
        userSupplyData_.expandPercent = (userSupply_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_EXPAND_PERCENT) & X14;
        userSupplyData_.expandDuration = (userSupply_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_EXPAND_DURATION) & X24;
        userSupplyData_.baseWithdrawalLimit = BigMathMinified.fromBigNumber(
            (userSupply_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_BASE_WITHDRAWAL_LIMIT) & X18,
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK
        );

        if (userSupplyData_.modeWithInterest) {
            // convert raw amounts to normal for withInterest mode
            userSupplyData_.supply =
                (userSupplyData_.supply * overallTokenData_.supplyExchangePrice) /
                EXCHANGE_PRICES_PRECISION;
            userSupplyData_.withdrawalLimit =
                (userSupplyData_.withdrawalLimit * overallTokenData_.supplyExchangePrice) /
                EXCHANGE_PRICES_PRECISION;
            userSupplyData_.baseWithdrawalLimit =
                (userSupplyData_.baseWithdrawalLimit * overallTokenData_.supplyExchangePrice) /
                EXCHANGE_PRICES_PRECISION;
        }

        userSupplyData_.withdrawableUntilLimit = userSupplyData_.supply - userSupplyData_.withdrawalLimit;
        uint balanceOf_ = token_ == _NATIVE_TOKEN_ADDRESS
            ? address(LIQUIDITY).balance
            : TokenInterface(token_).balanceOf(address(LIQUIDITY));

        userSupplyData_.withdrawable = balanceOf_ > userSupplyData_.withdrawableUntilLimit
            ? userSupplyData_.withdrawableUntilLimit
            : balanceOf_;
    }

    /// @inheritdoc ILiquidityResolver
    function getUserMultipleSupplyData(
        address user_,
        address[] calldata tokens_
    )
        public
        view
        returns (
            Structs.UserSupplyData[] memory userSuppliesData_,
            Structs.OverallTokenData[] memory overallTokensData_
        )
    {
        uint256 length_ = tokens_.length;
        userSuppliesData_ = new Structs.UserSupplyData[](length_);
        overallTokensData_ = new Structs.OverallTokenData[](length_);

        for (uint256 i; i < length_; i++) {
            (userSuppliesData_[i], overallTokensData_[i]) = getUserSupplyData(user_, tokens_[i]);
        }
    }

    /// @inheritdoc ILiquidityResolver
    function getUserBorrowData(
        address user_,
        address token_
    )
        public
        view
        returns (Structs.UserBorrowData memory userBorrowData_, Structs.OverallTokenData memory overallTokenData_)
    {
        overallTokenData_ = getOverallTokenData(token_);
        uint256 userBorrow_ = getUserBorrow(user_, token_);

        userBorrowData_.modeWithInterest = userBorrow_ & 1 == 1;

        userBorrowData_.borrow = BigMathMinified.fromBigNumber(
            (userBorrow_ >> LiquiditySlotsLink.BITS_USER_BORROW_AMOUNT) & X64,
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK
        );

        // get updated expanded borrow limit
        userBorrowData_.borrowLimit = LiquidityCalcs.calcBorrowLimitBeforeOperate(userBorrow_, userBorrowData_.borrow);

        userBorrowData_.lastUpdateTimestamp =
            (userBorrow_ >> LiquiditySlotsLink.BITS_USER_BORROW_LAST_UPDATE_TIMESTAMP) &
            X33;
        userBorrowData_.expandPercent = (userBorrow_ >> LiquiditySlotsLink.BITS_USER_BORROW_EXPAND_PERCENT) & X14;
        userBorrowData_.expandDuration = (userBorrow_ >> LiquiditySlotsLink.BITS_USER_BORROW_EXPAND_DURATION) & X24;
        userBorrowData_.baseBorrowLimit = BigMathMinified.fromBigNumber(
            (userBorrow_ >> LiquiditySlotsLink.BITS_USER_BORROW_BASE_BORROW_LIMIT) & X18,
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK
        );
        userBorrowData_.maxBorrowLimit = BigMathMinified.fromBigNumber(
            (userBorrow_ >> LiquiditySlotsLink.BITS_USER_BORROW_MAX_BORROW_LIMIT) & X18,
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK
        );

        if (userBorrowData_.modeWithInterest) {
            // convert raw amounts to normal for withInterest mode
            userBorrowData_.borrow =
                (userBorrowData_.borrow * overallTokenData_.borrowExchangePrice) /
                EXCHANGE_PRICES_PRECISION;
            userBorrowData_.borrowLimit =
                (userBorrowData_.borrowLimit * overallTokenData_.borrowExchangePrice) /
                EXCHANGE_PRICES_PRECISION;
            userBorrowData_.baseBorrowLimit =
                (userBorrowData_.baseBorrowLimit * overallTokenData_.borrowExchangePrice) /
                EXCHANGE_PRICES_PRECISION;
            userBorrowData_.maxBorrowLimit =
                (userBorrowData_.maxBorrowLimit * overallTokenData_.borrowExchangePrice) /
                EXCHANGE_PRICES_PRECISION;
        }

        userBorrowData_.borrowableUntilLimit = userBorrowData_.borrowLimit - userBorrowData_.borrow;
        uint balanceOf_ = token_ == _NATIVE_TOKEN_ADDRESS
            ? address(LIQUIDITY).balance
            : TokenInterface(token_).balanceOf(address(LIQUIDITY));

        userBorrowData_.borrowable = balanceOf_ > userBorrowData_.borrowableUntilLimit
            ? userBorrowData_.borrowableUntilLimit
            : balanceOf_;
    }

    /// @inheritdoc ILiquidityResolver
    function getUserMultipleBorrowData(
        address user_,
        address[] calldata tokens_
    )
        public
        view
        returns (
            Structs.UserBorrowData[] memory userBorrowingsData_,
            Structs.OverallTokenData[] memory overallTokensData_
        )
    {
        uint256 length_ = tokens_.length;
        userBorrowingsData_ = new UserBorrowData[](length_);

        for (uint256 i; i < length_; i++) {
            (userBorrowingsData_[i], overallTokensData_[i]) = getUserBorrowData(user_, tokens_[i]);
        }
    }

    /// @inheritdoc ILiquidityResolver
    function getUserMultipleBorrowSupplyData(
        address user_,
        address[] calldata supplyTokens_,
        address[] calldata borrowTokens_
    )
        public
        view
        returns (
            Structs.UserSupplyData[] memory userSuppliesData_,
            Structs.OverallTokenData[] memory overallSupplyTokensData_,
            Structs.UserBorrowData[] memory userBorrowingsData_,
            Structs.OverallTokenData[] memory overallBorrowTokensData_
        )
    {
        uint256 length_ = supplyTokens_.length;
        userSuppliesData_ = new Structs.UserSupplyData[](length_);
        overallSupplyTokensData_ = new Structs.OverallTokenData[](length_);
        for (uint256 i; i < length_; i++) {
            (userSuppliesData_[i], overallSupplyTokensData_[i]) = getUserSupplyData(user_, supplyTokens_[i]);
        }

        length_ = borrowTokens_.length;
        userBorrowingsData_ = new UserBorrowData[](length_);
        overallBorrowTokensData_ = new Structs.OverallTokenData[](length_);
        for (uint256 i; i < length_; i++) {
            (userBorrowingsData_[i], overallBorrowTokensData_[i]) = getUserBorrowData(user_, borrowTokens_[i]);
        }
    }
}
