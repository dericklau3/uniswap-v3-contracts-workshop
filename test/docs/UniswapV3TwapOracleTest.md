# UniswapV3TwapOracle Tests

## Purpose

`test/UniswapV3TwapOracle.t.sol` 在固定以太坊主网 fork 上验证
`UniswapV3TwapOracle`，所有代币和池均使用真实主网合约。

## Fork Setup

- 主网区块：`24_361_930`
- Uniswap V3 Factory：`0x1F98431c8aD98523631AE4a59f267346ea31F984`
- 池费率：`3000`，即 `0.3%`
- 基础币：主网 USDT
- 计价币：主网 WETH 和 WBTC

测试通过 Factory 的 `getPool` 获取 WETH/USDT 与 WBTC/USDT 池，不硬编码池地址。

## Configuration Scenarios

测试验证：

- 构造函数保存真实 USDT、owner 和目标 observation 容量。
- 构造函数拒绝零地址 owner 与零地址基础币。
- 只有 owner 可以调用 `setPool`。
- `setPool` 拒绝零地址、非合约地址、基础币本身以及不匹配的真实池。
- WETH/USDT 池容量不足时，`observationCardinalityNext` 被真实扩容。
- WBTC/USDT 池容量已达标时，扩容调用被跳过。

## TWAP Scenarios

WETH 与 WBTC 价格均直接调用真实池的 `observe([3600, 0])`，验证一小时 TWAP。
返回价格统一为 18 位精度，并通过足够宽的合理价格区间断言避免测试依赖精确市场价格。

运行测试需要 `foundry.toml` 中的 `mainnet` RPC 配置可用，或本机已有对应 fork 数据缓存。
