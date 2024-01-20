// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { LiquidityCalcs } from "../../../libraries/liquidityCalcs.sol";
import { ILendingFactory } from "../../../protocols/lending/interfaces/iLendingFactory.sol";
import { ILendingRewardsRateModel } from "../../../protocols/lending/interfaces/iLendingRewardsRateModel.sol";
import { Structs as LendingRewardsRateModelStructs } from "../../../protocols/lending/lendingRewardsRateModel/structs.sol";
import { ILiquidity } from "../../../liquidity/interfaces/iLiquidity.sol";
import { IAllowanceTransfer } from "../../../protocols/lending/interfaces/permit2/iAllowanceTransfer.sol";
import { IIToken, IITokenNativeUnderlying } from "../../../protocols/lending/interfaces/iIToken.sol";
import { ILiquidityResolver } from "../../../periphery/resolvers/liquidity/iLiquidityResolver.sol";
import { Structs as LiquidityStructs } from "../../../periphery/resolvers/liquidity/structs.sol";
import { ILendingResolver } from "./iLendingResolver.sol";
import { Structs } from "./structs.sol";

/// @notice Fluid Lending protocol (iTokens) resolver
/// Implements various view-only methods to give easy access to Lending protocol data.
contract LendingResolver is ILendingResolver, Structs {
    /// @dev address that is mapped to the chain native token
    address internal constant _NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @inheritdoc ILendingResolver
    ILendingFactory public immutable LENDING_FACTORY;

    /// @inheritdoc ILendingResolver
    ILiquidityResolver public immutable LIQUIDITY_RESOLVER;

    /// @notice thrown if an input param address is zero
    error LendingResolver__AddressZero();

    /// @notice constructor sets the immutable `LENDING_FACTORY` address
    constructor(ILendingFactory lendingFactory_, ILiquidityResolver liquidityResolver_) {
        if (address(lendingFactory_) == address(0) || address(liquidityResolver_) == address(0)) {
            revert LendingResolver__AddressZero();
        }
        LENDING_FACTORY = lendingFactory_;
        LIQUIDITY_RESOLVER = liquidityResolver_;
    }

    /// @inheritdoc ILendingResolver
    function isLendingFactoryAuth(address auth_) external view returns (bool) {
        return LENDING_FACTORY.isAuth(auth_);
    }

    /// @inheritdoc ILendingResolver
    function isLendingFactoryDeployer(address deployer_) external view returns (bool) {
        return LENDING_FACTORY.isDeployer(deployer_);
    }

    /// @inheritdoc ILendingResolver
    function getAllITokenTypes() public view returns (string[] memory) {
        return LENDING_FACTORY.iTokenTypes();
    }

    /// @inheritdoc ILendingResolver
    function getAllITokens() public view returns (address[] memory) {
        return LENDING_FACTORY.allTokens();
    }

    /// @inheritdoc ILendingResolver
    function computeIToken(address asset_, string calldata iTokenType_) external view returns (address) {
        return LENDING_FACTORY.computeToken(asset_, iTokenType_);
    }

    /// @inheritdoc ILendingResolver
    function getITokenDetails(IIToken iToken_) public view returns (ITokenDetails memory iTokenDetails_) {
        address underlying_ = iToken_.asset();

        bool isNativeUnderlying_ = false;
        try IITokenNativeUnderlying(address(iToken_)).NATIVE_TOKEN_ADDRESS() {
            // if NATIVE_TOKEN_ADDRESS is defined, iTokenType must be NativeUnderlying.
            isNativeUnderlying_ = true;
        } catch {}

        bool supportsEIP2612Deposits_ = false;
        try IERC20Permit(underlying_).DOMAIN_SEPARATOR() {
            // if DOMAIN_SEPARATOR is defined, we assume underlying supports EIP2612. Not a 100% guarantee
            supportsEIP2612Deposits_ = true;
        } catch {}

        (, uint256 rewardsRate_) = getITokenRewards(iToken_);
        (
            LiquidityStructs.UserSupplyData memory userSupplyData_,
            LiquidityStructs.OverallTokenData memory overallTokenData_
        ) = LIQUIDITY_RESOLVER.getUserSupplyData(
                address(iToken_),
                isNativeUnderlying_ ? _NATIVE_TOKEN_ADDRESS : underlying_
            );

        uint256 totalAssets_ = iToken_.totalAssets();

        iTokenDetails_ = ITokenDetails(
            address(iToken_),
            supportsEIP2612Deposits_,
            isNativeUnderlying_,
            iToken_.name(),
            iToken_.symbol(),
            iToken_.decimals(),
            underlying_,
            totalAssets_,
            iToken_.totalSupply(),
            iToken_.convertToShares(10 ** iToken_.decimals()), // example convertToShares for 10 ** decimals
            iToken_.convertToAssets(10 ** iToken_.decimals()), // example convertToAssets for 10 ** decimals
            rewardsRate_,
            overallTokenData_.supplyRate,
            int256(userSupplyData_.supply) - int256(totalAssets_), // rebalanceDifference
            userSupplyData_
        );

        return iTokenDetails_;
    }

    /// @inheritdoc ILendingResolver
    function getITokenInternalData(
        IIToken iToken_
    )
        public
        view
        returns (
            ILiquidity liquidity_,
            ILendingFactory lendingFactory_,
            ILendingRewardsRateModel lendingRewardsRateModel_,
            IAllowanceTransfer permit2_,
            address rebalancer_,
            bool rewardsActive_,
            uint256 liquidityBalance_,
            uint256 liquidityExchangePrice_,
            uint256 tokenExchangePrice_
        )
    {
        return iToken_.getData();
    }

    /// @inheritdoc ILendingResolver
    function getITokensEntireData() public view returns (ITokenDetails[] memory) {
        address[] memory allTokens = getAllITokens();
        ITokenDetails[] memory iTokenDetailsArr_ = new ITokenDetails[](allTokens.length);
        for (uint256 i = 0; i < allTokens.length; ) {
            iTokenDetailsArr_[i] = getITokenDetails(IIToken(allTokens[i]));
            unchecked {
                i++;
            }
        }
        return iTokenDetailsArr_;
    }

    /// @inheritdoc ILendingResolver
    function getUserPositions(address user_) external view returns (ITokenDetailsUserPosition[] memory) {
        ITokenDetails[] memory iTokensEntireData_ = getITokensEntireData();
        ITokenDetailsUserPosition[] memory userPositionArr_ = new ITokenDetailsUserPosition[](
            iTokensEntireData_.length
        );
        for (uint256 i = 0; i < iTokensEntireData_.length; ) {
            userPositionArr_[i].iTokenDetails = iTokensEntireData_[i];
            userPositionArr_[i].userPosition = getUserPosition(IIToken(iTokensEntireData_[i].tokenAddress), user_);
            unchecked {
                i++;
            }
        }
        return userPositionArr_;
    }

    /// @inheritdoc ILendingResolver
    function getITokenRewards(
        IIToken iToken_
    ) public view returns (ILendingRewardsRateModel rewardsRateModel_, uint256 rewardsRate_) {
        bool rewardsActive_;
        (, , rewardsRateModel_, , , rewardsActive_, , , ) = iToken_.getData();

        if (rewardsActive_) {
            (rewardsRate_, , ) = rewardsRateModel_.getRate(iToken_.totalAssets());
        }
    }

    /// @inheritdoc ILendingResolver
    function getITokenRewardsRateModelConfig(
        IIToken iToken_
    ) public view returns (LendingRewardsRateModelStructs.Config memory rewardsRateModelConfig_) {
        ILendingRewardsRateModel rewardsRateModel_;
        (, , rewardsRateModel_, , , , , , ) = iToken_.getData();

        if (address(rewardsRateModel_) != address(0)) {
            rewardsRateModelConfig_ = rewardsRateModel_.getConfig();
        }
    }

    /// @inheritdoc ILendingResolver
    function getUserPosition(IIToken iToken_, address user_) public view returns (UserPosition memory userPosition) {
        IERC20 underlying_ = IERC20(iToken_.asset());

        userPosition.iTokenShares = iToken_.balanceOf(user_);
        userPosition.underlyingAssets = iToken_.convertToAssets(userPosition.iTokenShares);
        userPosition.underlyingBalance = underlying_.balanceOf(user_);
        userPosition.allowance = underlying_.allowance(user_, address(iToken_));
    }

    /// @inheritdoc ILendingResolver
    function getPreviews(
        IIToken iToken_,
        uint256 assets_,
        uint256 shares_
    )
        public
        view
        returns (uint256 previewDeposit_, uint256 previewMint_, uint256 previewWithdraw_, uint256 previewRedeem_)
    {
        previewDeposit_ = iToken_.previewDeposit(assets_);
        previewMint_ = iToken_.previewMint(shares_);
        previewWithdraw_ = iToken_.previewWithdraw(assets_);
        previewRedeem_ = iToken_.previewRedeem(shares_);
    }
}
