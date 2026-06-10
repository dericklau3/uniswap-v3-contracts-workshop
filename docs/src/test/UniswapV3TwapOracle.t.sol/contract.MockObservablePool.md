# MockObservablePool
[Git Source](https://github.com/dericklau3/uniswap-v3-contracts-workshop/blob/ea1e6b95fd3bd1697200950ba44ef189dc8acf20/test/UniswapV3TwapOracle.t.sol)


## State Variables
### token0

```solidity
address public immutable token0
```


### token1

```solidity
address public immutable token1
```


### insufficientHistory

```solidity
bool public insufficientHistory
```


### arithmeticMeanTick

```solidity
int24 public arithmeticMeanTick
```


## Functions
### constructor


```solidity
constructor(address token0_, address token1_) ;
```

### setInsufficientHistory


```solidity
function setInsufficientHistory(bool insufficientHistory_) external;
```

### setArithmeticMeanTick


```solidity
function setArithmeticMeanTick(int24 arithmeticMeanTick_) external;
```

### observe


```solidity
function observe(uint32[] calldata secondsAgos)
    external
    view
    returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s);
```

## Errors
### InvalidPeriod

```solidity
error InvalidPeriod();
```

### InsufficientHistory

```solidity
error InsufficientHistory();
```

