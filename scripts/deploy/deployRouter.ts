import { ethers, run } from "hardhat";
import { readJson, deployContract, executeTx } from "../utils";

async function main() {

    const [deployer] = await ethers.getSigners();

    const path = "config/contracts.json";
    

    const options = {signer: deployer}

    await deployContract("UniswapInterfaceMulticall", "uniswapInterfaceMulticall", options, null, [])
    await deployContract("ProxyAdmin", "proxyAdmin", options, null, [])
    await deployContract("TickLens", "tickLens", options, null, [])
    await deployContract("NFTDescriptor", "nftDescriptor", options, null, [])

    let contracts = readJson(path)
    
    const nftPositionDescriptorImplArgs = {
        weth: contracts.weth.address
    };
    await deployContract(
        "NonfungibleTokenPositionDescriptor",
        "nonfungibleTokenPositionDescriptorImpl",
        { signer: deployer, libraries: { NFTDescriptor: contracts.nftDescriptor.address }},
        nftPositionDescriptorImplArgs,
        [[nftPositionDescriptorImplArgs.weth]]
    )

    contracts = readJson(path)
    const nftPositionDescriptorArgs = {
        logic: contracts.nonfungibleTokenPositionDescriptorImpl.address,
        admin: contracts.proxyAdmin.address,
        data: "0x"
    };
    await deployContract("TransparentUpgradeableProxy", "nonfungibleTokenPositionDescriptor", options, nftPositionDescriptorArgs, [[
        nftPositionDescriptorArgs.logic,
        nftPositionDescriptorArgs.admin,
        nftPositionDescriptorArgs.data
    ]])

    contracts = readJson(path)
    const nonfungiblePositionManagerArgs = {
        factory: contracts.uniswapV3Factory.address,
        weth: contracts.weth.address,
        tokenDescriptor: contracts.nonfungibleTokenPositionDescriptor.address
    };
    await deployContract("NonfungiblePositionManager", "nonfungiblePositionManager", options, nonfungiblePositionManagerArgs, [[
        nonfungiblePositionManagerArgs.factory,
        nonfungiblePositionManagerArgs.weth,
        nonfungiblePositionManagerArgs.tokenDescriptor
    ]])

    contracts = readJson(path)
    const v3MigratorArgs = {
        factory: contracts.uniswapV3Factory.address,
        weth: contracts.weth.address,
        nonfungiblePositionManager: contracts.nonfungiblePositionManager.address
    };
    await deployContract("V3Migrator", "v3Migrator", options, v3MigratorArgs, [[
        v3MigratorArgs.factory,
        v3MigratorArgs.weth,
        v3MigratorArgs.nonfungiblePositionManager
    ]])

    const quoterArgs = {
        factory: contracts.uniswapV3Factory.address,
        weth: contracts.weth.address
    };
    await deployContract("contracts/v3-periphery/lens/Quoter.sol:Quoter", "quoter", options, quoterArgs, [[
        quoterArgs.factory,
        quoterArgs.weth
    ]])

    const quoterV2Args = {
        factory: contracts.uniswapV3Factory.address,
        weth: contracts.weth.address
    };
    await deployContract("contracts/v3-periphery/lens/QuoterV2.sol:QuoterV2", "quoterV2", options, quoterV2Args, [[
        quoterV2Args.factory,
        quoterV2Args.weth
    ]])

    const swapRouterArgs = {
        factory: contracts.uniswapV3Factory.address,
        weth: contracts.weth.address
    };
    await deployContract("SwapRouter", "swapRouter", options, swapRouterArgs, [[
        swapRouterArgs.factory,
        swapRouterArgs.weth
    ]])

    const swapRouter02Args = {
        v2Facotry: contracts.uniswapV2Factory.address,
        factory: contracts.uniswapV3Factory.address,
        positionManager: contracts.nonfungiblePositionManager.address,
        weth: contracts.weth.address
    };
    await deployContract("SwapRouter02", "swapRouter02", options, swapRouter02Args, [[
        swapRouter02Args.v2Facotry,
        swapRouter02Args.factory,
        swapRouter02Args.positionManager,
        swapRouter02Args.weth
    ]])
    console.log("finished");
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});