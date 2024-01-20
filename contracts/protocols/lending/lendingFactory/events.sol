// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { ILendingFactory } from "../interfaces/iLendingFactory.sol";

abstract contract Events {
    /// @notice emitted when a new iToken is created
    event LogTokenCreated(address indexed token, address indexed asset, uint256 indexed count, string iTokenType);

    /// @notice emitted when an auth is modified by owner
    event LogSetAuth(address indexed auth, bool indexed allowed);

    /// @notice emitted when a deployer is modified by owner
    event LogSetDeployer(address indexed deployer, bool indexed allowed);

    /// @notice emitted when the creation code for an iTokenType is set
    event LogSetITokenCreationCode(string indexed iTokenType, address indexed creationCodePointer);
}
