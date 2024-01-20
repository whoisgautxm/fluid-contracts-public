// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { ILendingFactory } from "../../../protocols/lending/interfaces/iLendingFactory.sol";
import { Structs as LiquidityResolverStructs } from "../liquidity/structs.sol";

abstract contract Structs {
    struct ITokenDetails {
        address tokenAddress;
        bool eip2612Deposits;
        bool isNativeUnderlying;
        string name;
        string symbol;
        uint256 decimals;
        address asset;
        uint256 totalAssets;
        uint256 totalSupply;
        uint256 convertToShares;
        uint256 convertToAssets;
        // additional yield from rewards, if active
        uint256 rewardsRate;
        // yield at Liquidity
        uint256 supplyRate;
        // difference between iToken assets & actual deposit at Liquidity. (supplyAtLiquidity - totalAssets).
        // if negative, rewards must be funded to guarantee withdrawal is possible for all users. This happens
        // by executing rebalance().
        int256 rebalanceDifference;
        // liquidity related data such as supply amount, limits, expansion etc.
        LiquidityResolverStructs.UserSupplyData liquidityUserSupplyData;
    }

    struct UserPosition {
        uint256 iTokenShares;
        uint256 underlyingAssets;
        uint256 underlyingBalance;
        uint256 allowance;
    }

    struct ITokenDetailsUserPosition {
        ITokenDetails iTokenDetails;
        UserPosition userPosition;
    }
}
