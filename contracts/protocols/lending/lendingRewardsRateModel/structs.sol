// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

abstract contract Structs {
    /// @notice struct to set rewards rate data
    struct RateDataParams {
        ///
        /// @param kink1 first kink in rewards rate. in token decimals
        /// TVL below kink 1 usually means slow decrease in rewards rate, once TVL is above kink 1 rewards rate decreases faster
        /// same applies to kink2 and kink3
        uint256 kink1;
        ///
        /// @param kink2 second kink in rewards rate. in token decimals. This must be after kink1.
        uint256 kink2;
        ///
        /// @param kink3 third kink in rewards rate. in token decimals. This must be after kink2.
        uint256 kink3;
        ///
        /// @param rateZeroAtTVL point in TVL when rewards rate reaches 0. This must be after kink3.
        uint256 rateZeroAtTVL;
        ///
        /// @param rateAtTVLZero desired reward rate when TVL is zero. in 1e2: 100% = 10_000; 1% = 100
        /// e.g. at TVL = 0.0001 rate would be at 15%. rateAtTVLZero would be 1_500 then.
        /// This should be the highest possible APR
        uint256 rateAtTVLZero;
        ///
        /// @param rateAtTVLKink1 desired rewards rate when TVL is at first kink. in 1e2: 100% = 10_000; 1% = 100
        /// e.g. when rate should be 12% at first kink then rateAtTVLKink1 would be 1_200
        uint256 rateAtTVLKink1;
        ///
        /// @param rateAtTVLKink2 desired rewards rate when TVL is at second kink. in 1e2: 100% = 10_000; 1% = 100
        /// e.g. when rate should be 7% at second kink then rateAtTVLKink2 would be 700
        uint256 rateAtTVLKink2;
        ///
        /// @param rateAtTVLKink3 desired rewards rate when TVL is at third kink. in 1e2: 100% = 10_000; 1% = 100
        /// e.g. when rate should be 4% at third kink then rateAtTVLKink3 would be 400
        uint256 rateAtTVLKink3;
    }

    /// @notice Configuration structure for the rewards rate model.
    struct Config {
        /// @param assetDecimals Base unit for the asset
        uint256 assetDecimals;
        /// @param maxRate Max rate
        uint256 maxRate;
        /// @param startTime The start time for rewards: rewards are 0 before this.
        uint256 startTime;
        /// @param endTime The end time for rewards: rewards are 0 after this.
        uint256 endTime;
        /// @param kink1 The first kink in rewards rate, in token decimals.
        /// TVL below kink1 usually means a slow decrease in rewards rate, once TVL is above kink1 rewards rate decreases faster.
        uint256 kink1;
        /// @param kink2 The second kink in rewards rate, in token decimals. This must be after kink1.
        uint256 kink2;
        /// @param kink3 The third kink in rewards rate, in token decimals. This must be after kink2.
        uint256 kink3;
        /// @param rateZeroAtTVL The point in TVL when rewards rate reaches 0. This must be after kink3.
        uint256 rateZeroAtTVL;
        /// @param slope1 The slope for the first segment of the rewards rate model.
        uint256 slope1;
        /// @param slope2 The slope for the second segment of the rewards rate model.
        uint256 slope2;
        /// @param slope3 The slope for the third segment of the rewards rate model.
        uint256 slope3;
        /// @param slope4 The slope for the fourth segment of the rewards rate model.
        uint256 slope4;
        /// @param constant1 The constant for the first segment of the rewards rate model.
        uint256 constant1;
        /// @param constant2 The constant for the second segment of the rewards rate model.
        uint256 constant2;
        /// @param constant3 The constant for the third segment of the rewards rate model.
        uint256 constant3;
        /// @param constant4 The constant for the fourth segment of the rewards rate model.
        uint256 constant4;
    }
}
