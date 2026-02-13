## Deployment Tutorial

```
# 1. install dependcies
yarn

# 2. write configuration
cp .env.example .env

# 3. deploy UniswapV3Factory
npx hardhat run scripts/deploy/deployFactory.ts --network bsctest

# 5. Replace the POOL_INIT_CODE_HASH of PoolAddress

# 6. deploy UniswapV3SwapRouter
npx hardhat run scripts/deploy/deployRouter.ts --network bsctest
```