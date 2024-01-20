// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

library ErrorTypes {
    /***********************************|
    |   UniV3CheckFallbackCLRSOracle    | 
    |__________________________________*/

    /// @notice thrown when the delta between main price source and check rate source is exceeding the allowed delta
    uint256 internal constant UniV3CheckFallbackCLRSOracle__InvalidPrice = 60001;

    /// @notice thrown when an invalid parameter is passed to a method
    uint256 internal constant UniV3CheckFallbackCLRSOracle__InvalidParams = 60002;

    /***********************************|
    |          Chainlink Oracle         | 
    |__________________________________*/

    /// @notice thrown when an invalid parameter is passed to a method
    uint256 internal constant ChainlinkOracle__InvalidParams = 61001;

    /***********************************|
    |          UniswapV3 Oracle         | 
    |__________________________________*/

    /// @notice thrown when an invalid parameter is passed to a method
    uint256 internal constant UniV3Oracle__InvalidParams = 62001;

    /// @notice thrown when TWAP price deviation is exceeding the allowed delta
    uint256 internal constant UniV3Oracle__InvalidPrice = 62002;

    /// @notice thrown when constructor is called with invalid ordered seconds agos values
    uint256 internal constant UniV3Oracle__InvalidSecondsAgos = 62003;

    /// @notice thrown when constructor is called with invalid delta values > 100%
    uint256 internal constant UniV3Oracle__InvalidDeltas = 62004;

    /// @notice thrown when POOL.observe() call fails
    uint256 internal constant UniV3Oracle__ObserveCallFailed = 62005;

    /***********************************|
    |            WstETh Oracle          | 
    |__________________________________*/

    /// @notice thrown when an invalid parameter is passed to a method
    uint256 internal constant WstETHOracle__InvalidParams = 63001;

    /***********************************|
    |           Redstone Oracle         | 
    |__________________________________*/

    /// @notice thrown when an invalid parameter is passed to a method
    uint256 internal constant RedstoneOracle__InvalidParams = 64001;

    /***********************************|
    |          Fallback Oracle          | 
    |__________________________________*/

    /// @notice thrown when an invalid parameter is passed to a method
    uint256 internal constant FallbackOracle__InvalidParams = 65001;

    /***********************************|
    |       FallbackCLRSOracle          | 
    |__________________________________*/

    /// @notice thrown when the exchange rate is zero, even for the fallback oracle source (if enabled)
    uint256 internal constant FallbackCLRSOracle__ExchangeRateZero = 66001;

    /***********************************|
    |         WstETHCLRSOracle          | 
    |__________________________________*/

    /// @notice thrown when the exchange rate is zero, even for the fallback oracle source (if enabled)
    uint256 internal constant WstETHCLRSOracle__ExchangeRateZero = 67001;
}
