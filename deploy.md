## Deployment Tutorial

```
# 1. install dependencies
bun install

# 2. write configuration
cp .env.example .env

bunx hardhat compile

# 3. deploy UniswapV3Factory
bunx hardhat run scripts/deploy/deployFactory.ts --network bsctest

# 5. Replace the POOL_INIT_CODE_HASH of PoolAddress

# 6. deploy UniswapV3SwapRouter
bunx hardhat run scripts/deploy/deployRouter.ts --network bsctest
```
