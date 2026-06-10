# Library 中文注释 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `contracts` 下全部 library 合约的英文注释本地化为中文，并为复杂代码补充准确的业务解释。

**Architecture:** 按 core、periphery、swap-router 三个互不重叠的目录组实施。所有变更限制在注释层，完成后通过源代码去注释对比、英文残留扫描和 Foundry 命令验证。

**Tech Stack:** Solidity、NatSpec、Foundry、ripgrep、git diff

---

### Task 1: Core libraries

**Files:**
- Modify: `contracts/v3-core/libraries/*.sol`

- [ ] 翻译全部英文 NatSpec 和行内注释。
- [ ] 为 `FullMath`、`Oracle`、`SqrtPriceMath`、`SwapMath`、`Tick`、`TickBitmap`、`TickMath` 补充业务解释。
- [ ] 检查该目录没有非注释代码变化。

### Task 2: Periphery libraries

**Files:**
- Modify: `contracts/v3-periphery/libraries/*.sol`

- [ ] 翻译全部英文 NatSpec 和行内注释。
- [ ] 为 `LiquidityAmounts`、`NFTDescriptor`、`NFTSVG`、`OracleLibrary`、`Path`、`PositionValue` 补充业务解释。
- [ ] 检查该目录没有非注释代码变化。

### Task 3: Swap Router libraries

**Files:**
- Modify: `contracts/swap-router/libraries/*.sol`

- [ ] 翻译全部英文 NatSpec 和行内注释。
- [ ] 为 tick 跨越计数和 V2 池地址、储备、报价逻辑补充业务解释。
- [ ] 检查该目录没有非注释代码变化。

### Task 4: Repository verification

**Files:**
- Verify: `contracts/**/libraries/*.sol`

- [ ] 扫描并处理英文注释残留。
- [ ] 运行 `forge fmt --check`。
- [ ] 运行 `forge build`。
- [ ] 运行 `forge doc --build`。
- [ ] 运行 `git diff --check` 并复核最终 diff。
