// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

library ErrorTypes {
    /***********************************|
    |               iToken              | 
    |__________________________________*/

    /// @notice thrown when a deposit amount is too small to increase BigMath stored balance in Liquidity.
    /// precision of BigMath is 1e12, so if token holds 120_000_000_000 USDC, min amount to make a difference would be 0.1 USDC.
    /// i.e. user would send a very small deposit which mints no shares -> revert
    uint256 internal constant iToken__DepositInsignificant = 20001;

    /// @notice thrown when minimum output amount is not reached, e.g. for minimum shares minted (deposit) or
    ///         minimum assets received (redeem)
    uint256 internal constant iToken__MinAmountOut = 20002;

    /// @notice thrown when maximum amount is surpassed, e.g. for maximum shares burned (withdraw) or
    ///         maximum assets input (mint)
    uint256 internal constant iToken__MaxAmount = 20003;

    /// @notice thrown when invalid params are sent to a method, e.g. zero address
    uint256 internal constant iToken__InvalidParams = 20004;

    /// @notice thrown when a rounding error is caught that might cause adverse effects
    uint256 internal constant iToken__RoundingError = 20005;

    /// @notice thrown when an unauthorized caller is trying to execute an auth-protected method
    uint256 internal constant iToken__Unauthorized = 20006;

    /// @notice thrown when a with permit / signature method is called from msg.sender that is the owner.
    /// Should call the method without permit instead if msg.sender is the owner.
    uint256 internal constant iToken__PermitFromOwnerCall = 20007;

    /// @notice thrown when a reentrancy is detected.
    uint256 internal constant iToken__Reentrancy = 20008;

    /// @notice thrown when _tokenExchangePrice overflows type(uint64).max
    uint256 internal constant iToken__ExchangePriceOverflow = 20009;

    /// @notice thrown when msg.sender is not rebalancer
    uint256 internal constant iToken__NotRebalancer = 20010;

    /// @notice thrown when rebalance is called with msg.value > 0 for non NativeUnderlying iToken
    uint256 internal constant iToken__NotNativeUnderlying = 20011;

    /// @notice thrown when the received new liquidity exchange price is of unexpected value (< than the old one)
    uint256 internal constant iToken__LiquidityExchangePriceUnexpected = 20012;

    /***********************************|
    |     iToken Native Underlying      | 
    |__________________________________*/

    /// @notice thrown when native deposit is called but sent along `msg.value` does not cover the deposit amount
    uint256 internal constant iTokenNativeUnderlying__TransferInsufficient = 21001;

    /// @notice thrown when a liquidity callback is called for a native token operation
    uint256 internal constant iTokenNativeUnderlying__UnexpectedLiquidityCallback = 21002;

    /***********************************|
    |         Lending Factory         | 
    |__________________________________*/

    /// @notice thrown when a method is called with invalid params
    uint256 internal constant LendingFactory__InvalidParams = 22001;

    /// @notice thrown when the provided input param address is zero
    uint256 internal constant LendingFactory__ZeroAddress = 22002;

    /// @notice thrown when the token already exists
    uint256 internal constant LendingFactory__TokenExists = 22003;

    /// @notice thrown when the iToken has not yet been configured at Liquidity
    uint256 internal constant LendingFactory__LiquidityNotConfigured = 22004;

    /// @notice thrown when an unauthorized caller is trying to execute an auth-protected method
    uint256 internal constant LendingFactory__Unauthorized = 22005;

    /***********************************|
    |   Lending Rewards Rate Model      | 
    |__________________________________*/

    /// @notice thrown when invalid params are given as input
    uint256 internal constant LendingRewardsRateModel__InvalidParams = 23001;

    /// @notice thrown when calculated rewards rate is exceeding the maximum rate
    uint256 internal constant LendingRewardsRateModel__MaxRate = 23002;
}
