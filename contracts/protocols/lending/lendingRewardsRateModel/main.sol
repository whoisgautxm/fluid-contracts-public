// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { ILendingRewardsRateModel } from "../interfaces/iLendingRewardsRateModel.sol";
import { ErrorTypes } from "../errorTypes.sol";
import { Error } from "../error.sol";
import { Structs } from "./structs.sol";

/// @title LendingRewardsRateModel
/// @notice Calculates rewards rates based on 3 kinks, 4 slopes, and 4 constants model for absolute numbers in TVL.
/// @dev rate is in 1e12 in percent per year, e.g. 1e14 == 100%
/// For example, at 0 USDC, the distribution should be 20%;
/// at 10M USDC (kink1), the distribution should be 10%;
/// at 50M USDC (kink2), the distribution should be 5%;
/// at 100M USDC (kink3), the distribution should be 3%;
/// and after this, the model will continue dilution as TVL grows until rewards reach zero at a certain TVL ("rateZeroAtTVL").
contract LendingRewardsRateModel is ILendingRewardsRateModel, Structs, Error {
    /// @dev precision decimals for percentage values
    uint256 internal constant INPUT_PARAMS_PERCENT_PRECISION = 1e2;

    /// @dev precision decimals for rewards rate
    uint256 internal constant RATE_PRECISION = 1e12;

    /// @dev maximum rewards rate is 25%. no config higher than this should be possible.
    uint256 internal constant MAX_RATE = 25 * RATE_PRECISION; // 1e12 = 1%, this is 25%.

    /// @dev base unit for the asset, e.g., 1e18 for DAI, 1e6 for USDC (decimals)
    uint256 internal immutable ASSET_DECIMALS;

    /// @dev start time for rewards: rewards are 0 before this
    uint256 internal immutable START_TIME;

    /// @dev end time for rewards: rewards are 0 after this
    uint256 internal immutable END_TIME;

    /// @dev kinks have to be the same decimals as underlying iToken asset, e.g. USDC 6 decimals or 18 for DAI
    uint256 internal immutable KINK1;
    uint256 internal immutable KINK2;
    uint256 internal immutable KINK3;
    uint256 internal immutable RATE_ZERO_AT_TVL;

    /// @dev slopes are at 1e12 RATE_PRECISION. slopes are always negative, but we do that right in the getRate formula instead
    // of storing here as int256, to be more gas efficient (no conversion to uin256 needed)
    uint256 internal immutable SLOPE1;
    uint256 internal immutable SLOPE2;
    uint256 internal immutable SLOPE3;
    uint256 internal immutable SLOPE4;

    /// @dev constants are at 1e12 RATE_PRECISION
    uint256 internal immutable CONSTANT1;
    uint256 internal immutable CONSTANT2;
    uint256 internal immutable CONSTANT3;
    uint256 internal immutable CONSTANT4;

    /// @notice sets immutable vars for rewards rate config based on input params.
    /// @param decimals_  underlying asset decimals (e.g. USDC 6 decimals or 18 for DAI)
    /// @param startTime_ start time for rewards: rewards are 0 before this
    /// @param endTime_   end time for rewards: rewards are 0 after this
    /// @param rateData_  rate data struct containing info for kinks and desired rates at each TVL point
    constructor(uint256 decimals_, uint256 startTime_, uint256 endTime_, Structs.RateDataParams memory rateData_) {
        // sanity checks
        if (decimals_ == 0 || startTime_ == 0 || endTime_ == 0 || startTime_ > endTime_) {
            revert FluidLendingError(ErrorTypes.LendingRewardsRateModel__InvalidParams);
        }

        // kinks must not be >= next kink (would lead to underflow or division by 0)
        if (
            rateData_.kink1 >= rateData_.kink2 ||
            rateData_.kink2 >= rateData_.kink3 ||
            rateData_.kink3 >= rateData_.rateZeroAtTVL
        ) {
            revert FluidLendingError(ErrorTypes.LendingRewardsRateModel__InvalidParams);
        }

        // rate at zero must not be > MAX_RATE (25%)
        if (rateData_.rateAtTVLZero > MAX_RATE) {
            revert FluidLendingError(ErrorTypes.LendingRewardsRateModel__MaxRate);
        }
        // rewards are diminishing as TVL increases.
        if (
            rateData_.rateAtTVLZero < rateData_.rateAtTVLKink1 ||
            rateData_.rateAtTVLKink1 < rateData_.rateAtTVLKink2 ||
            rateData_.rateAtTVLKink2 < rateData_.rateAtTVLKink3
        ) {
            revert FluidLendingError(ErrorTypes.LendingRewardsRateModel__InvalidParams);
        }

        ASSET_DECIMALS = decimals_;
        START_TIME = startTime_;
        END_TIME = endTime_;

        // store TVL points
        KINK1 = rateData_.kink1;
        KINK2 = rateData_.kink2;
        KINK3 = rateData_.kink3;
        RATE_ZERO_AT_TVL = rateData_.rateZeroAtTVL;

        // slope and constant must be multiplied by RATE_PRECISION minus input param precision of percentage "rateAt..." values
        // to get to final desired precision RATE_PRECISION
        uint256 precisionAdjustment_ = RATE_PRECISION / INPUT_PARAMS_PERCENT_PRECISION; // 1e12 / 1e2

        // goal is to get to a formula y = mx +c, where m = slope, c = constant, x = TVL and y = rewards rate
        // for the first part of the rate when TVL < kink1; the constant1 of the formula is "rateAtTVLZero"
        CONSTANT1 = rateData_.rateAtTVLZero * precisionAdjustment_;

        // to get slope we can transform the formula to slope = (rate - constant) / TVL
        // or we simply know the difference in rate that should occur per difference in TVL. slope = diff in Rate / diff in TVL.
        SLOPE1 =
            ((rateData_.rateAtTVLZero - rateData_.rateAtTVLKink1) * precisionAdjustment_ * decimals_) /
            (rateData_.kink1);
        // * decimals_ to balance out division by kink,
        // * precisionAdjustment_ to get to final RATE_PRECISION decimals

        // slope2 is when kink1 < TVL < kink2. We know the rate at kink1 and the rate at kink2, so:
        // slope2 = (rateAtKink2 - rateAtKink1) / (kink2 - kink1). denominator is TVL range
        SLOPE2 =
            ((rateData_.rateAtTVLKink1 - rateData_.rateAtTVLKink2) * precisionAdjustment_ * decimals_) /
            (rateData_.kink2 - rateData_.kink1);

        // to get constant2, transform formula again: c = y - mx; which is constant = rate - slope * TVL; so:
        // constant2 = rateAtKink1 - slope2 * kink1. but slope is always negative so rateAtKink1 + slope2 * kink1
        CONSTANT2 = (rateData_.rateAtTVLKink1 * precisionAdjustment_) + ((SLOPE2 * rateData_.kink1) / decimals_);

        // same for slope and constant 3 & 4.
        SLOPE3 =
            ((rateData_.rateAtTVLKink2 - rateData_.rateAtTVLKink3) * precisionAdjustment_ * decimals_) /
            (rateData_.kink3 - rateData_.kink2);

        CONSTANT3 = (rateData_.rateAtTVLKink2 * precisionAdjustment_) + ((SLOPE3 * rateData_.kink2) / decimals_);

        SLOPE4 =
            (rateData_.rateAtTVLKink3 * precisionAdjustment_ * decimals_) /
            (rateData_.rateZeroAtTVL - rateData_.kink3);

        CONSTANT4 = (rateData_.rateAtTVLKink3 * precisionAdjustment_) + ((SLOPE4 * rateData_.kink3) / decimals_);
    }

    /// @inheritdoc ILendingRewardsRateModel
    function getConfig() external view returns (Structs.Config memory config_) {
        config_.assetDecimals = ASSET_DECIMALS;
        config_.maxRate = MAX_RATE;
        config_.startTime = START_TIME;
        config_.endTime = END_TIME;
        config_.kink1 = KINK1;
        config_.kink2 = KINK2;
        config_.kink3 = KINK3;
        config_.rateZeroAtTVL = RATE_ZERO_AT_TVL;
        config_.slope1 = SLOPE1;
        config_.slope2 = SLOPE2;
        config_.slope3 = SLOPE3;
        config_.slope4 = SLOPE4;
        config_.constant1 = CONSTANT1;
        config_.constant2 = CONSTANT2;
        config_.constant3 = CONSTANT3;
        config_.constant4 = CONSTANT4;
        return config_;
    }

    /// @inheritdoc ILendingRewardsRateModel
    function getRate(uint256 totalAssets_) public view returns (uint256 rate_, bool ended_, uint256 startTime_) {
        if (block.timestamp > END_TIME) {
            return (0, true, START_TIME);
        } else if (block.timestamp < START_TIME || totalAssets_ > RATE_ZERO_AT_TVL) {
            return (0, false, START_TIME);
        }

        uint256 slope_;
        uint256 constant_;

        // kinks have the same decimals as totalAssets so no conversion needed for direct comparison of the two
        if (totalAssets_ > KINK3) {
            slope_ = SLOPE4;
            constant_ = CONSTANT4;
        } else if (totalAssets_ > KINK2) {
            slope_ = SLOPE3;
            constant_ = CONSTANT3;
        } else if (totalAssets_ > KINK1) {
            slope_ = SLOPE2;
            constant_ = CONSTANT2;
        } else {
            slope_ = SLOPE1;
            constant_ = CONSTANT1;
        }

        // y = mx + c. but m is always negative but we store it as positive. so: y = -mx +c;
        // or y = c - mx; so:
        rate_ = constant_ - ((slope_ * totalAssets_) / ASSET_DECIMALS);
        // slope & constant are in RATE_PRECISION so result is also in RATE_PRECISION

        return (rate_, false, START_TIME);
    }
}
