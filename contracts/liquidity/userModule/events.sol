// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

contract Events {
    /// @notice emitted on any `operate()` execution: deposit / supply / withdraw / borrow.
    /// includes info related to the executed operation, new total amounts (packed uint256 of BigMath numbers as in storage)
    /// and exchange prices (packed uint256 as in storage).
    event LogOperate(
        address indexed user,
        address indexed token,
        int256 supplyAmount,
        int256 borrowAmount,
        address withdrawTo,
        address borrowTo,
        uint256 totalAmounts,
        uint256 exchangePricesAndConfig
    );
}
