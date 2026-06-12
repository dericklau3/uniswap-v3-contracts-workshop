## Uniswap V3

### 公式

#### sqrtPriceX96

```
token0 < token1
sqrtPriceX96 = Math.sqrt(token1Amount * 2**192 / token0Amount)
```

#### tickLower & tickUpper

```
price = token1 / token0

rawLowerPrice = lowerPrice * 10^decimals1 / 10^decimals0
rawUpperPrice = upperPrice * 10^decimals1 / 10^decimals0

lowerTickRaw = log(rawLowerPrice) / log(1.0001)
upperTickRaw = log(rawUpperPrice) / log(1.0001)

tickLower = floor(lowerTickRaw / tickSpacing) * tickSpacing
tickUpper = ceil(upperTickRaw / tickSpacing) * tickSpacing

tickLower 向下取整，确保覆盖 lowerPrice
tickUpper 向上取整，确保覆盖 upperPrice
```



### 理解

#### fee 与 tickSpacing的关系

```
    0.01% -> 1
    feeAmountTickSpacing[100] = 1;
    0.05% -> 10
    feeAmountTickSpacing[500] = 10;
    0.3% -> 60    tickSpacing * 6
    feeAmountTickSpacing[3000] = 60;
    1% -> 200     tickSpacing * 6
    feeAmountTickSpacing[10000] = 200;
```

Uniswap V3 的价格不是连续存储的，而是用 tick 表示价格区间。
每个 tick 代表一个价格点，价格大概满足：

```
price = 1.0001 ^ tick
```

`tickSpacing` 决定 LP 添加流动性时，tick 必须按多少间隔来选。

```
tickSpacing = 60;
那么用户只能选择：
..., -120, -60, 0, 60, 120, 180 ...
```

tickSpacing 越小，价格区间越细，LP 可以更精细地集中流动性。
 tickSpacing 越大，价格区间越粗，LP 只能放更宽的流动性区间。



#### tickSpacing、maxLiquidityPerTick 、MinTick、MaxTick 的关系

Uniswap V3 的 tick 有最大最小范围：

```
TickMath.MIN_TICK = -887272;
TickMath.MAX_TICK =  887272;
```

不同手续费档位有不同的 `tickSpacing`

```
fee = 3000 = 0.3%   tickSpacing = 60;
```

那么合法 tick 必须是 60 的倍数。

在当前 tickSpacing 下，最小和最大的可用 tick。

```
int24 minTick = (TickMath.MIN_TICK / tickSpacing) * tickSpacing;
int24 maxTick = (TickMath.MAX_TICK / tickSpacing) * tickSpacing;
minTick = -887220
maxTick =  887220
```

这是计算当前 `tickSpacing` 下，总共有多少个可用 tick。

所以当 `tickSpacing = 60` 的时候，整个 Uniswap V3 价格范围内大概有 `29575` 个可用 tick。

```
uint24 numTicks = uint24((maxTick - minTick) / tickSpacing) + 1;
numTicks = (887220 - (-887220)) / 60 + 1
         = 1774440 / 60 + 1
         = 29574 + 1
         = 29575
```

maxLiquidityPerTick = 把 `uint128` 最大流动性平均分配给所有可用 tick，得到每个 tick 最多允许的流动性。

这样可以保证：所有 tick 的 liquidityGross 加起来，也不会超过 uint128 最大值

```
type(uint128).max / numTicks;
maxLiquidityPerTick = uint128最大值 / 可用tick数量
```

Uniswap V3 每个 tick 里会记录一个值：uint128 liquidityGross; 以这个 tick 作为边界的总流动性数量。

比如很多 LP 都使用同一个价格区间：[1800, 2000]

那么 lower tick 和 upper tick 上都会累加很多 `liquidityGross`。

如果没有限制，某个 tick 的 `liquidityGross` 可能会无限增加，超过 `uint128` 最大值，导致溢出。

**tickSpacing 越大，maxLiquidityPerTick 越大** 因为 tickSpacing 越大，可用 tick 数量越少。

```
tickSpacing 越小 → 可用 tick 越多 → 每个 tick 平均上限越低
tickSpacing 越大 → 可用 tick 越少 → 每个 tick 平均上限越高
```

对于 0.3% 手续费池，也就是 `tickSpacing = 60` 的池子，每个 tick 上最多允许大约 `1.15e34` 的 liquidityGross。

```
int24 minTick = (TickMath.MIN_TICK / 60) * 60;
int24 maxTick = (TickMath.MAX_TICK / 60) * 60;
uint24 numTicks = uint24((maxTick - minTick) / 60) + 1;
return type(uint128).max / numTicks;

minTick = -887220
maxTick = 887220
numTicks = 29575
maxLiquidityPerTick ≈ 1.15e34
```



#### TickMath

##### getSqrtRatioAtTick

如果已知 `tick`，那么可以推 sqrtPriceX96：

Uniswap V3 里，价格和 tick 的关系是：

```
price = 1.0001 ^ tick
```

但是合约内部不用普通价格，而是用价格的平方根：

```
sqrtPrice = sqrt(1.0001 ^ tick)
sqrtPrice = 1.0001 ^ (tick / 2)
```

为了避免小数，Uniswap V3 使用 Q64.96 定点数保存：

```
sqrtPriceX96 = sqrtPrice * 2^96
sqrtPriceX96 = sqrt(1.0001 ^ tick) * 2^96
```

##### getTickAtSqrtRatio

如果已知 `sqrtPriceX96`，那么可以推 tick：

```
sqrtPrice = sqrtPriceX96 / 2^96
sqrtPrice = 1.0001 ^ (tick / 2)
```

两边取 log,  log的作用可以理解为：**把指数从右上角“拿下来”，变成乘法。**  2^3 = 8.   log₂(8) = 3

Math.log(8)  = 2.0794415416798357 的意思是 e 的多少次方 = 8， 等价于问：e^? = 8  `e` 是一个固定常数 e ≈ 2.718281828459045

2.718281828459045 ^ 2.0794415416798357 ≈ 8

```
log(sqrtPrice) = log(1.0001 ^ (tick / 2))
# 根据对数的幂法则  log(a^b) = b * log(a)
log(1.0001 ^ (tick / 2)) = tick / 2 * log(1.0001)
# 两边除以 log(1.0001)
log(sqrtPrice) / log(1.0001) = tick / 2
# 两边再乘以 2
tick = 2 * log(sqrtPrice) / log(1.0001)
```



#### 价格区间 tickLower & tickUpper

```
sqrtPriceX96 = 当前池子价格
tickLower    = 你的流动性从哪个价格开始生效
tickUpper    = 你的流动性到哪个价格结束生效

# 它们必须是 tickSpacing 的整数倍
tickLower % tickSpacing == 0
tickUpper % tickSpacing == 0

MIN_TICK = -887272
MAX_TICK =  887272
```

##### 全区间

```
假设 tickSpacing = 60

tickLower = ceil(MIN_TICK / tickSpacing) * tickSpacing
tickUpper = floor(MAX_TICK / tickSpacing) * tickSpacing

tickLower = ceil(-887272 / 60) * 60
          = -14787 * 60
          = -887220

tickUpper = floor(887272 / 60) * 60
          = 14787 * 60
          = 887220
```

##### 自定义区间

tickerLower,tickUpper 的设置流程：

1. 确认 token0 / token1 顺序
2. 确认价格方向是 token1 / token0
3. 把 lowerPrice / upperPrice 转成 raw price
4. raw price 转 tick
5. tick 对齐 tickSpacing
6. 得到 tickLower / tickUpper

```
价格区间的价格计算 = token1 / token0 的价格
WETH = 18 decimals
USDT = 6 decimals

假设 token0 = WETH, token1 = USDT     1 WETH = 3000 USDT    [2500 - 3500]
lowerRawPrice = 2500 * 1e6 / 1e18 = token1Amount / token0Amount
tick = log(lowerRawPrice) / log(1.0001)
tick = log(2.5e-9) / log(1.0001)
     = -198079.65437324703
tickLower = Math.floor(tick / tickSpacing) * tickSpacing
tickLower = Math.floor(-198079.65437324703 / 60) * 60
          = -198120
          
upperRawPrice = 3500 * 1e6 / 1e18 = token1Amount / token0Amount
tick = log(upperRawPrice) / log(1.0001)
tick = log(3.5e-9) / log(1.0001)
     = -194714.76377372
tickUpper = Math.ceil(tick / tickSpacing) * tickSpacing
tickUpper = Math.floor(-194714.76377372 / 60) * 60
          = -194760
          
假设 token0 = USDT, token1 = WETH     1 USDT = 1 / 3000 WETH  [1/3500 - 1/2500]
1/3500 = 0.00028571428571428574
lowerRawPrice = 0.00028571428571428574 * 1e18 / 1e6 = token1Amount / token0Amount
tick = log(lowerRawPrice) / log(1.0001)
tick = log(285714285.71428573) / log(1.0001)
     = 194714.76377372
tickLower = Math.floor(tick / tickSpacing) * tickSpacing
tickLower = Math.floor(194714.76377372 / 60) * 60
          = 194700

1/2500 = 0.0004 
upperRawPrice = 0.0004 * 1e18 / 1e6 = token1Amount / token0Amount
tick = log(upperRawPrice) / log(1.0001)
tick = log(400000000) / log(1.0001)
     = 198079.65437324703
tickUpper = Math.ceil(tick / tickSpacing) * tickSpacing
tickUpper = Math.floor(198079.65437324703 / 60) * 60
          = 198060
```



#### 流动性计算 

V3-periphery/libraries/LiquidityAmounts.sol

##### 价格在区间内

```
Pa = tickLower 对应的价格
P  = 当前池子价格，也就是 initial price
Pb = tickUpper 对应的价格

Pa < P < Pb
tickLower < currentTick < tickUpper

sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
sqrtRatioX96  = pool 当前 sqrtPriceX96;
sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
```

根据liquidity计算 amount0, amount1 数量. `L` 就是 liquidity

```
amount0 = L * (sqrtB - sqrtP) / (sqrtP * sqrtB)
amount1 = L * (sqrtP - sqrtA)

token0 数量由 当前价格 P 到 上边界 Pb 决定
token1 数量由 下边界 Pa 到 当前价格 P 决定
```

输入token0数量，计算出添加流动性所需的token1数量

```
# 先用 amount0 反推出 liquidity：
L = amount0 * sqrtP * sqrtB / (sqrtB - sqrtP)
# 然后用这个 L 算 amount1：
amount1 = L * (sqrtP - sqrtA)
```

输入token1数量，计算出添加流动性所需的token0数量

```
# 先用 amount1 反推出 liquidity：
L = amount1 / (sqrtP - sqrtA)
# 然后用这个 L 算 amount0：
amount0 = L * (sqrtB - sqrtP) / (sqrtP * sqrtB)
```

#####  价格在区间外

###### 当前价格 低于 区间

```
P <= Pa
currentTick <= tickLower
这时候你的流动性全部由 token0 组成。

amount0 = L * (sqrtB - sqrtA) / (sqrtA * sqrtB)
amount1 = 0
```

###### 当前价格 高于 区间

```
P >= Pb
currentTick >= tickUpper
这时候你的流动性全部由 token1 组成。

amount0 = 0
amount1 = L * (sqrtB - sqrtA)
```

##### 最大流动性限制

`UniswapV3Pool.mint()` 里没有直接限制；限制在 `Tick.update()` 里，通过 `_updatePosition()` 把 `maxLiquidityPerTick` 传进去，最终检查 `liquidityGrossAfter <= maxLiquidityPerTick`

