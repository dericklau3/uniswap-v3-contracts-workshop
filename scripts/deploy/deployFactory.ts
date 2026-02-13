import { ethers, run } from "hardhat";
import { readJson, deployContract, executeTx } from "../utils";

async function main() {

    const [deployer] = await ethers.getSigners();

    const path = "config/contracts.json";


    const options = { signer: deployer }
    await deployContract("UniswapV3Factory", "uniswapV3Factory", options, null, [])

    let contracts = readJson(path)
    const uniswapV3Factory = await ethers.getContractAt("UniswapV3Factory", contracts.uniswapV3Factory.address, deployer);
    // After deploying, obtain the INIT_CODE_PAIR_HASH and proceed to modify POOL_INIT_CODE_HASH in v3-periphery/libraries/PoolAddress
    const pairHash = await uniswapV3Factory.INIT_CODE_PAIR_HASH();
    console.log("pairHash: ", pairHash);
    console.log("finished");
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});