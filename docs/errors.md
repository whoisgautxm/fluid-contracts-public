# Error structure for Fluid contracts

## Overview

In this project, errors are organized systematically to enhance clarity and ease of reference. Each protocol or module within a protocol has its dedicated set of error definitions and types.

## Structuring Errors

### 1. `error.sol` File

For each protocol in the project, there should be an `error.sol` file. This file contains an abstract error contract, which can be inherited by the entire protocol.

**Template:**

```solidity
//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

abstract contract Error {
    error Fluid<protocol-name>Error(uint256 errorId_);
}
```

**Example for the Lending protocol:**

```solidity
//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

abstract contract Error {
  error FluidLendingError(uint256 errorId_);
}
```

### 2. `errorTypes.sol` File

This file defines a library with constant variables corresponding to error IDs for each protocol or module.

**Template:**

```solidity
//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

library ErrorTypes {

    /***********************************|
    |         <module-name>             |
    |__________________________________*/

    /// @notice <error-description>
    uint256 internal constant <Module__ErrorName> = {X}000{Y};

    // ... Additional errors ...

}
```

**Example using the Liquidity Factory module:**

```solidity
//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

library ErrorTypes {
  /***********************************|
    |         Lending Factory         | 
    |__________________________________*/

  /// @notice thrown when a method is called with invalid params
  uint256 internal constant LendingFactory__InvalidParams = 22001;

  /// @notice thrown when the provided input param address is zero
  uint256 internal constant LendingFactory__ZeroAddress = 22002;

  /// @notice thrown when the token already exists
  uint256 internal constant LendingFactory__TokenExists = 22003;

  // ... Additional errors ...
}
```

## Error IDs Specification

To maintain consistency and avoid clashes, we follow a unique numbering system for error IDs. Each protocol or even each contract within a protocol gets a distinct range.

For instance:

- **Liquidity Protocol**:
  - **Liquidity UserModule module:** 10001, 10002, 10003, etc.
  - **Liquidity AdminModule module:** 11001, 11002, 11003, etc.
- **Lending Protocol**:
  - **Lending IToken module:** 20001, 20002, 20003, etc.
  - **Lending LendingFactory module:** 21001, 21002, etc.

By adhering to this structure, developers can easily trace errors back to their source module and protocol, simplifying debugging and maintenance.

## Error ID Ranges

### 1. Liquidity Protocol -

- **Admin Module** - Prefix: AdminModule\_\_:
  - **Range:** 10001-10999
- **User Module** - Prefix: UserModule\_\_:
  - **Range:** 11001-11999
- **Helpers** - Prefix: LiquidityHelpers\_\_:
  - **Range:** 12001-12999

### 2. Lending Protocol

- **iToken Module** - Prefix: iToken\_\_:
  - **Range:** 20001-20999
- **iToken Native Underlying Module** - Prefix: iTokenNativeUnderlying\_\_:
  - **Range:** 21001-21999
- **Lending Factory Module** - Prefix: LendingFactory\_\_:
  - **Range:** 22001-22999
- **Lending Rewards Rate Model Module** - Prefix: LendingRewardsRate\_\_:
  - **Range:** 23001-23999

### 3. Vault Protocol

- **Vault Factory Module** - Prefix: VaultFactory\_\_:
  - **Range:** 30001-30999
- **VaultT1 Module** - Prefix: VaultT1\_\_:
  - **Range:** 31001-31999
- **ERC721 Module** - Prefix: ERC721\_\_:
  - **Range:** 32001-32999
- **VaultT1 Admin** - Prefix: VaultT1Admin\_\_:
  - **Range:** 33001-33999

### 5. InfiniteProxy Protocol - Prefix: InfiniteProxy\_\_

- **Range:** 50001-50999

### 6. Oracles

- **UniV3CheckFallbackCLRSOracle oracle module** - Prefix: UniV3CheckFallbackCLRSOracle\_\_:
  - **Range:** 60001-60999
- **Chainlink oracle module** - Prefix: ChainlinkOracle\_\_:
  - **Range:** 61001-61999
- **UniV3Oracle oracle module** - Prefix: UniV3Oracle\_\_:
  - **Range:** 62001-62999
- **WstETh oracle module** - Prefix: WstETHOracle\_\_:
  - **Range:** 63001-63999
- **Redstone oracle module** - Prefix: RedstoneOracle\_\_:
  - **Range:** 64001-64999
- **Fallback oracle module** - Prefix: FallbackOracle\_\_:
  - **Range:** 65001-65999
- **FallbackCLRS oracle module** - Prefix: FallbackCLRSOracle\_\_:
  - **Range:** 66001-66999
- **WstETHCLRS oracle module** - Prefix: WstETHCLRSOracle\_\_:
  - **Range:** 67001-67999

### 7. Libraries

- **LiquidityCalcs** - Prefix: LiquidityCalcs\_\_:
  - **Range:** 70001-70999
- **SafeTransfer** - Prefix: SafeTransfer\_\_:
  - **Range:** 71001-71999
