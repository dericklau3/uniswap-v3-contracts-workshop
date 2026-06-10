# UniswapV3TwapOracleTest
[Git Source](https://github.com/dericklau3/uniswap-v3-contracts-workshop/blob/ea1e6b95fd3bd1697200950ba44ef189dc8acf20/test/UniswapV3TwapOracle.t.sol)

**Inherits:**
Test


## State Variables
### owner

```solidity
address internal owner = makeAddr("owner")
```


### stranger

```solidity
address internal stranger = makeAddr("stranger")
```


### quoteToken

```solidity
MockMetadataToken internal quoteToken
```


### token

```solidity
MockMetadataToken internal token
```


### oracle

```solidity
UniswapV3TwapOracle internal oracle
```


## Functions
### setUp


```solidity
function setUp() public;
```

### test_ConstructorSetsConfiguration


```solidity
function test_ConstructorSetsConfiguration() public;
```

### test_ConstructorRevertsForZeroQuoteToken


```solidity
function test_ConstructorRevertsForZeroQuoteToken() public;
```

### test_ConstructorRevertsForZeroOwner


```solidity
function test_ConstructorRevertsForZeroOwner() public;
```

### test_ConstructorRevertsForUnsupportedQuoteTokenDecimals


```solidity
function test_ConstructorRevertsForUnsupportedQuoteTokenDecimals() public;
```

### test_SetPoolStoresPoolAndEmitsEvent


```solidity
function test_SetPoolStoresPoolAndEmitsEvent() public;
```

### test_SetPoolReplacesExistingPool


```solidity
function test_SetPoolReplacesExistingPool() public;
```

### test_SetPoolRevertsForNonOwner


```solidity
function test_SetPoolRevertsForNonOwner() public;
```

### test_SetPoolRevertsForZeroToken


```solidity
function test_SetPoolRevertsForZeroToken() public;
```

### test_SetPoolRevertsForZeroPool


```solidity
function test_SetPoolRevertsForZeroPool() public;
```

### test_SetPoolRevertsWhenTokenIsQuoteToken


```solidity
function test_SetPoolRevertsWhenTokenIsQuoteToken() public;
```

### test_SetPoolRevertsForNonContractPool


```solidity
function test_SetPoolRevertsForNonContractPool() public;
```

### test_SetPoolRevertsForMismatchedPair


```solidity
function test_SetPoolRevertsForMismatchedPair() public;
```

### test_SetPoolRevertsForUnsupportedTokenDecimals


```solidity
function test_SetPoolRevertsForUnsupportedTokenDecimals() public;
```

### test_GetPriceUsesTwelveHourTwapAndNormalizesEighteenBySixDecimals


```solidity
function test_GetPriceUsesTwelveHourTwapAndNormalizesEighteenBySixDecimals() public;
```

### test_GetPriceNormalizesEightBySixDecimals


```solidity
function test_GetPriceNormalizesEightBySixDecimals() public;
```

### test_GetPriceSupportsReversePoolTokenOrdering


```solidity
function test_GetPriceSupportsReversePoolTokenOrdering() public;
```

### test_GetPriceRevertsWhenPoolIsNotConfigured


```solidity
function test_GetPriceRevertsWhenPoolIsNotConfigured() public;
```

### test_GetPricePropagatesInsufficientHistoryFailure


```solidity
function test_GetPricePropagatesInsufficientHistoryFailure() public;
```

## Events
### PoolSet

```solidity
event PoolSet(address indexed token, address indexed pool);
```

