# UniswapV3TwapOracle
[Git Source](https://github.com/dericklau3/uniswap-v3-contracts-workshop/blob/ea1e6b95fd3bd1697200950ba44ef189dc8acf20/test/UniswapV3TwapOracle.sol)

**Inherits:**
Ownable2Step

**Title:**
Uniswap V3 12 小时时间加权平均价格预言机

使用同一个不可变基础币为已配置的代币计价，并将所有价格统一为 18 位精度。


## State Variables
### TWAP_PERIOD
固定的 TWAP 观察窗口，单位为秒。


```solidity
uint32 public constant TWAP_PERIOD = 12 hours
```


### quoteToken
当前部署中所有价格统一使用的基础币。


```solidity
address public immutable quoteToken
```


### quoteTokenDecimals

```solidity
uint8 internal immutable quoteTokenDecimals
```


### pools
返回指定代币已配置的 Uniswap V3 池。


```solidity
mapping(address token => address pool) public pools
```


### tokenDecimals

```solidity
mapping(address token => uint8 decimals) internal tokenDecimals
```


## Functions
### constructor

使用指定 owner 和当前链的基础币创建预言机。


```solidity
constructor(address initialOwner, address quoteToken_) Ownable(initialOwner);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`initialOwner`|`address`|有权配置代币池的账户。|
|`quoteToken_`|`address`|所有已配置池统一使用的 USDC、USDT 或其他基础币。|


### setPool

设置或替换用于计算 `token` 价格的 Uniswap V3 池。

该池必须只包含 `token` 和不可变的 `quoteToken`，且仅 owner 可以调用。


```solidity
function setPool(address token, address pool) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|需要计价的代币。|
|`pool`|`address`|作为 12 小时价格观察来源的 Uniswap V3 池。|


### getPrice

返回一个完整 `token` 的 12 小时 TWAP，并以基础币计价。

返回值始终为 18 位精度；Uniswap 观察数据不足等错误会原样向上传递。


```solidity
function getPrice(address token) external view returns (uint256 price);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|已配置池并需要查询价格的代币。|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`price`|`uint256`|一个完整代币对应的基础币价值，统一为 18 位精度。|


## Events
### PoolSet
owner 设置或替换代币计价池时触发。


```solidity
event PoolSet(address indexed token, address indexed pool);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|需要查询价格的代币。|
|`pool`|`address`|同时包含 `token` 和 `quoteToken` 的 Uniswap V3 池。|

