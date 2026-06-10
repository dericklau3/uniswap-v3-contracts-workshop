# Library 中文注释设计

## 目标

将 `contracts/**/libraries/*.sol` 中的英文 NatSpec 和行内注释改为中文，并为难以理解的数学、位图、预言机、交换步骤、头寸计费和 NFT 展示逻辑补充业务解释。

## 范围

- `contracts/v3-core/libraries/*.sol`
- `contracts/v3-periphery/libraries/*.sol`
- `contracts/swap-router/libraries/*.sol`

不处理接口、测试合约或上述目录之外的普通合约。

## 编辑规则

- 仅修改或新增注释，不修改 Solidity 代码、字符串常量、错误码和公式。
- 保留 SPDX 标识、NatSpec 标签、标识符、数学符号、单位和链接。
- `@title`、`@notice`、`@dev`、`@param`、`@return` 后的说明改为中文。
- 复杂逻辑的补注应解释它在 Uniswap V3 业务中的作用，而不只复述语句。
- 已有中文注释保留，并在必要时统一措辞。

## 重点说明

- core：tick 状态、tick bitmap、Q64.96 价格、单 tick 交换、预言机环形缓冲区、手续费增长和 512 位精度运算。
- periphery：路径编码、池地址推导、报价预言机、头寸价值、NFT 数值格式化和 SVG 元数据生成。
- swap-router：V2 池地址与储备计算、跨越已初始化 tick 的 gas 估算和路由器哨兵常量。

## 验证

1. 检查目标文件 diff，确认没有非注释代码变化。
2. 扫描英文注释残留，人工判断专有名词、链接和公式是否应保留。
3. 运行 `forge fmt --check`。
4. 运行 `forge build`。
5. 运行 `forge doc --build`。
6. 运行 `git diff --check`。
