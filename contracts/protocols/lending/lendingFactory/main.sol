// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { CREATE3 } from "solmate/src/utils/CREATE3.sol";
import { SSTORE2 } from "solmate/src/utils/SSTORE2.sol";
import { Owned } from "solmate/src/auth/Owned.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { ILiquidity } from "../../../liquidity/interfaces/iLiquidity.sol";
import { ILendingFactory, ILendingFactoryAdmin } from "../interfaces/iLendingFactory.sol";
import { LiquiditySlotsLink } from "../../../libraries/liquiditySlotsLink.sol";
import { ErrorTypes } from "../errorTypes.sol";
import { Error } from "../error.sol";
import { Events } from "./events.sol";

abstract contract LendingFactoryVariables is Owned, Error, ILendingFactory {
    /*//////////////////////////////////////////////////////////////
                          CONSTANTS / IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ILendingFactory
    ILiquidity public immutable LIQUIDITY;

    /// @dev address that is mapped to the chain native token
    address internal constant _NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /*//////////////////////////////////////////////////////////////
                          STORAGE VARIABLES
    //////////////////////////////////////////////////////////////*/

    // ------------ storage variables from inherited contracts (Owned) come before vars here --------

    // ----------------------- slot 0 ---------------------------
    // address public owner;

    // 12 bytes empty

    // ----------------------- slot 1 ---------------------------
    /// @dev auths can update rewards related config at created iToken contracts.
    /// owner can add/remove auths.
    /// Owner is auth by default.
    mapping(address => uint256) internal _auths;

    // ----------------------- slot 2 ---------------------------
    /// @dev deployers can deploy new iTokens.
    /// owner can add/remove deployers.
    /// Owner is deployer by default.
    mapping(address => uint256) internal _deployers;

    // ----------------------- slot 3 ---------------------------
    /// @dev list of all created tokens.
    /// Solidity creates an automatic getter only to fetch at a certain position, so explicitly define a getter that returns all.
    address[] internal _allTokens;

    // ----------------------- slot 4 ---------------------------

    /// @dev available iTokenTypes for deployment. At least EIP2612Deposits, Permit2Deposits, NativeUnderlying.
    /// Solidity creates an automatic getter only to fetch at a certain position, so explicitly define a getter that returns all.
    string[] internal _iTokenTypes;

    // ----------------------- slot 5 ---------------------------

    /// @dev iToken creation code for each iTokenType, accessed via SSTORE2.
    /// maps keccak256(abi.encode(iTokenType)) -> SSTORE2 written creation code for the iToken contract
    mapping(bytes32 => address) internal _iTokenCreationCodePointers;

    /*//////////////////////////////////////////////////////////////
                          CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(ILiquidity liquidity_, address owner_) Owned(owner_) {
        if (owner_ == address(0)) {
            // Owned does not have a zero check for owner_
            revert FluidLendingError(ErrorTypes.LendingFactory__ZeroAddress);
        }

        LIQUIDITY = liquidity_;
    }

    /// @inheritdoc ILendingFactory
    function allTokens() public view returns (address[] memory) {
        return _allTokens;
    }

    /// @inheritdoc ILendingFactory
    function iTokenTypes() public view returns (string[] memory) {
        return _iTokenTypes;
    }

    /// @inheritdoc ILendingFactory
    function iTokenCreationCode(string memory iTokenType_) public view returns (bytes memory) {
        address creationCodePointer_ = _iTokenCreationCodePointers[keccak256(abi.encode(iTokenType_))];
        return creationCodePointer_ == address(0) ? new bytes(0) : SSTORE2.read(creationCodePointer_);
    }
}

abstract contract LendingFactoryAdmin is LendingFactoryVariables, Events {
    /// @dev validates that an address is not the zero address
    modifier validAddress(address value_) {
        if (value_ == address(0)) {
            revert FluidLendingError(ErrorTypes.LendingFactory__ZeroAddress);
        }
        _;
    }

    /// @dev validates that msg.sender is auth or owner
    modifier onlyAuths() {
        if (!isAuth(msg.sender)) {
            revert FluidLendingError(ErrorTypes.LendingFactory__Unauthorized);
        }
        _;
    }

    /// @dev validates that msg.sender is deployer or owner
    modifier onlyDeployers() {
        if (!isDeployer(msg.sender)) {
            revert FluidLendingError(ErrorTypes.LendingFactory__Unauthorized);
        }
        _;
    }

    /// @inheritdoc ILendingFactoryAdmin
    function isAuth(address auth_) public view returns (bool) {
        return auth_ == owner || _auths[auth_] == 1;
    }

    /// @inheritdoc ILendingFactoryAdmin
    function isDeployer(address deployer_) public view returns (bool) {
        return deployer_ == owner || _deployers[deployer_] == 1;
    }

    /// @inheritdoc ILendingFactoryAdmin
    function setAuth(address auth_, bool allowed_) external onlyOwner validAddress(auth_) {
        _auths[auth_] = allowed_ ? 1 : 0;

        emit LogSetAuth(auth_, allowed_);
    }

    /// @inheritdoc ILendingFactoryAdmin
    function setDeployer(address deployer_, bool allowed_) external onlyOwner validAddress(deployer_) {
        _deployers[deployer_] = allowed_ ? 1 : 0;

        emit LogSetDeployer(deployer_, allowed_);
    }

    /// @inheritdoc ILendingFactoryAdmin
    function setITokenCreationCode(string memory iTokenType_, bytes calldata creationCode_) external onlyAuths {
        uint256 length_ = _iTokenTypes.length;
        bytes32 iTokenTypeHash_ = keccak256(abi.encode(iTokenType_));

        if (creationCode_.length == 0) {
            // remove any previously stored creation code for `iTokenType_`
            delete _iTokenCreationCodePointers[keccak256(abi.encode(iTokenType_))];

            // remove key from array _iTokenTypes. _iTokenTypes is most likely an array of very few elements,
            // where setITokenCreationCode is a rarely called method and the removal of an iTokenType is even more rare.
            // So gas cost is not really an issue here but even if it were, this should still be cheaper than having
            // an additional mapping like with an OpenZeppelin EnumerableSet
            for (uint256 i; i < length_; ++i) {
                if (keccak256(abi.encode(_iTokenTypes[i])) == iTokenTypeHash_) {
                    _iTokenTypes[i] = _iTokenTypes[length_ - 1];
                    _iTokenTypes.pop();
                    break;
                }
            }

            emit LogSetITokenCreationCode(iTokenType_, address(0));
        } else {
            // write creation code to SSTORE2 pointer and set in mapping
            address creationCodePointer_ = SSTORE2.write(creationCode_);
            _iTokenCreationCodePointers[keccak256(abi.encode(iTokenType_))] = creationCodePointer_;

            // make sure `iTokenType_` is present in array _iTokenTypes
            bool isPresent_;
            for (uint256 i; i < length_; ++i) {
                if (keccak256(abi.encode(_iTokenTypes[i])) == iTokenTypeHash_) {
                    isPresent_ = true;
                    break;
                }
            }
            if (!isPresent_) {
                _iTokenTypes.push(iTokenType_);
            }

            emit LogSetITokenCreationCode(iTokenType_, creationCodePointer_);
        }
    }

    /// @inheritdoc ILendingFactoryAdmin
    function createToken(
        address asset_,
        string calldata iTokenType_,
        bool isNativeUnderlying_
    ) external validAddress(asset_) onlyDeployers returns (address token_) {
        address creationCodePointer_ = _iTokenCreationCodePointers[keccak256(abi.encode(iTokenType_))];
        if (creationCodePointer_ == address(0)) {
            revert FluidLendingError(ErrorTypes.LendingFactory__InvalidParams);
        }

        bytes32 salt_ = _getSalt(asset_, iTokenType_);

        if (Address.isContract(CREATE3.getDeployed(salt_))) {
            // revert if token already exists (Solmate CREATE3 does not check before deploying)
            revert FluidLendingError(ErrorTypes.LendingFactory__TokenExists);
        }

        bytes32 liquidityExchangePricesSlot_ = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT,
            // native underlying always uses the native token at Liquidity, but also supports WETH
            isNativeUnderlying_ ? _NATIVE_TOKEN_ADDRESS : asset_
        );
        if (LIQUIDITY.readFromStorage(liquidityExchangePricesSlot_) == 0) {
            // revert if iToken has not been configured at Liquidity contract yet (exchange prices config)
            revert FluidLendingError(ErrorTypes.LendingFactory__LiquidityNotConfigured);
        }

        // Use CREATE3 for deterministic deployments. Unfortunately it has 55k gas overhead
        token_ = CREATE3.deploy(
            salt_,
            abi.encodePacked(
                SSTORE2.read(creationCodePointer_), // creation code
                abi.encode(LIQUIDITY, address(this), asset_) // constructor params
            ),
            0
        );

        // Add the created token to the allTokens array
        _allTokens.push(token_);

        // Emit the TokenCreated event
        emit LogTokenCreated(token_, asset_, _allTokens.length, iTokenType_);
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @dev gets the CREATE3 salt for `asset_` and `iTokenType_`
    function _getSalt(address asset_, string calldata iTokenType_) internal pure returns (bytes32) {
        return keccak256(abi.encode(asset_, iTokenType_));
    }
}

/// @title Fluid LendingFactory
/// @notice creates Fluid lending protocol iTokens, which are interacting with Fluid Liquidity.
/// iTokens are ERC20 & ERC4626 compatible tokens that allow to deposit to Fluid Liquidity to earn interest.
/// Tokens are created at a deterministic address (see `computeToken()`), only executable by allow-listed auths.
/// @dev Note the deployed token starts out with no config at Liquidity contract.
/// This must be done by Liquidity auths in a separate step, otherwise no deposits will be possible.
/// This contract is not upgradeable. It supports adding new iToken creation codes for future new iToken types.
contract LendingFactory is LendingFactoryVariables, LendingFactoryAdmin {
    /// @notice initialize liquidity contract address & owner
    constructor(
        ILiquidity liquidity_,
        address owner_
    ) validAddress(address(liquidity_)) validAddress(owner) LendingFactoryVariables(liquidity_, owner_) {}

    /// @inheritdoc ILendingFactory
    function computeToken(address asset_, string calldata iTokenType_) public view returns (address token_) {
        return CREATE3.getDeployed(_getSalt(asset_, iTokenType_));
    }
}
