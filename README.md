# Uniswap V3 Contracts Workshops



### UniswapV3 debug

```
1.create position  2000 ETH + 9027911 DAI
https://dashboard.tenderly.co/tx/bnb-testnet/0x0f42a6c2fe5e0b0fa824c56f1489eefeadca2cbf9696975122f5b4bf3d422d2c

2.exactInput 1 ETH -> 3464 DAI
https://dashboard.tenderly.co/tx/bnb-testnet/0x99ee637e694628527b46e693729162fca9c996ccc544b45326aaaeccaaffbbd4

3.exactOutput
https://dashboard.tenderly.co/tx/bnb-testnet/0x7eb567b1eba0ff33171b3199347deff5f4b75ab2263ffeda539266155f90cd2e

4.mint
https://dashboard.tenderly.co/tx/bnb-testnet/0xa1d511abb3fcf8f2dd2df20694299ba951aa79fef658ed36a04430548cf0584b

5.cross-tick
https://dashboard.tenderly.co/tx/bnb-testnet/0x762232c2de3cd3aaf5bda6350f923646eec402b896a3c7d2d85a2d5fdba00e43
```


### sepolia

```
{
	"weth": {
		"address": "0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14"
	},
	"usdt": {
		"address": "0x9501Ee1B2320eF5d651f964ADC86F314E6c1aC48"
	},
	"uniswapV2Factory": {
		"address": "0x04E0459121DB7D49AE932428762a44B616E967D6",
		"args": {
			"feeToSetter": "0x4408e1c6745B43350711317C89Db35B479992e5C"
		}
	},
	"uniswapV2Router": {
		"address": "0x842f00Caae1f75aBECcAEc69c9c2c9f73E3d6C9A",
		"args": {
			"facotry": "0x04E0459121DB7D49AE932428762a44B616E967D6",
			"weth": "0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14"
		}
	},
	"uniswapV3Factory": {
		"address": "0x0227628f3F023bb0B980b67D528571c95c6DaC1c"
	},
	"uniswapInterfaceMulticall": {
		"address": ""
	},
	"proxyAdmin": {
		"address": "0x0b343475d44EC2b4b8243EBF81dc888BF0A14b36"
	},
	"tickLens": {
		"address": ""
	},
	"nftDescriptor": {
		"address": "0x3B5E3c5E595D85fbFBC2a42ECC091e183E76697C"
	},
	"nonfungibleTokenPositionDescriptorImpl": {
		"address": "0x5bE4DAa6982C69aD20A57F1e68cBcA3D37de6207",
		"args": {
			"weth": "0x04E0459121DB7D49AE932428762a44B616E967D6"
		}
	},
	"nonfungibleTokenPositionDescriptor": {
		"address": "",
		"args": {
			"logic": "0x3d36dB80c391bfa5A93D7944131E8d3a913C4b07",
			"admin": "0x885051b2B3fDe838F6166ae749bCcCbff231B8bB",
			"data": "0x"
		}
	},
	"nonfungiblePositionManager": {
		"address": "0x1238536071E1c677A632429e3655c799b22cDA52",
		"args": {
			"factory": "0xFB1370296ab08f5404653b57F845C73885574D63",
			"weth": "0x04E0459121DB7D49AE932428762a44B616E967D6",
			"tokenDescriptor": "0xdc9C1B65685daD4892661EEF68f446dfE54BDF36"
		}
	},
	"v3Migrator": {
		"address": "0x729004182cF005CEC8Bd85df140094b6aCbe8b15",
		"args": {
			"factory": "0xFB1370296ab08f5404653b57F845C73885574D63",
			"weth": "0x04E0459121DB7D49AE932428762a44B616E967D6",
			"nonfungiblePositionManager": "0x40A9776F35cfc9e02e6985b02b9586fE8357b369"
		}
	},
	"quoterV2": {
		"address": "0xEd1f6473345F45b75F8179591dd5bA1888cf2FB3",
		"args": {
			"factory": "0xFB1370296ab08f5404653b57F845C73885574D63",
			"weth": "0x04E0459121DB7D49AE932428762a44B616E967D6"
		}
	},
	"swapRouter": {
		"address": "0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E",
		"args": {
			"factory": "0xFB1370296ab08f5404653b57F845C73885574D63",
			"weth": "0x04E0459121DB7D49AE932428762a44B616E967D6"
		}
	}
}
```



### bsc test

```
{
	"weth": {
		"address": "0x04E0459121DB7D49AE932428762a44B616E967D6"
	},
	"usdt": {
		"address": "0xc48105A8BC482ade2822ED2c4159Cc85AF1249A1"
	},
	"uniswapV2Factory": {
		"address": "0x842f00Caae1f75aBECcAEc69c9c2c9f73E3d6C9A",
		"args": {
			"feeToSetter": "0x4408e1c6745B43350711317C89Db35B479992e5C"
		}
	},
	"uniswapV2Router": {
		"address": "0x68a5614cD96FE32485D4D5549d0bEd87a6765cF3",
		"args": {
			"facotry": "0x842f00Caae1f75aBECcAEc69c9c2c9f73E3d6C9A",
			"weth": "0x04E0459121DB7D49AE932428762a44B616E967D6"
		}
	},
	"uniswapV3Factory": {
		"address": "0xFB1370296ab08f5404653b57F845C73885574D63"
	},
	"uniswapInterfaceMulticall": {
		"address": "0x95da2e1591cAD0e320Ab9dd37F688c8667D63EAF"
	},
	"proxyAdmin": {
		"address": "0x885051b2B3fDe838F6166ae749bCcCbff231B8bB"
	},
	"tickLens": {
		"address": "0xF0683FEbEfE3186FCfeb4b04615Df603F9dd4a09"
	},
	"nftDescriptor": {
		"address": "0xc08AA111488630def496397d0056ea2b06A751F5"
	},
	"nonfungibleTokenPositionDescriptorImpl": {
		"address": "0x3d36dB80c391bfa5A93D7944131E8d3a913C4b07",
		"args": {
			"weth": "0x04E0459121DB7D49AE932428762a44B616E967D6"
		}
	},
	"nonfungibleTokenPositionDescriptor": {
		"address": "0xdc9C1B65685daD4892661EEF68f446dfE54BDF36",
		"args": {
			"logic": "0x3d36dB80c391bfa5A93D7944131E8d3a913C4b07",
			"admin": "0x885051b2B3fDe838F6166ae749bCcCbff231B8bB",
			"data": "0x"
		}
	},
	"nonfungiblePositionManager": {
		"address": "0x40A9776F35cfc9e02e6985b02b9586fE8357b369",
		"args": {
			"factory": "0xFB1370296ab08f5404653b57F845C73885574D63",
			"weth": "0x04E0459121DB7D49AE932428762a44B616E967D6",
			"tokenDescriptor": "0xdc9C1B65685daD4892661EEF68f446dfE54BDF36"
		}
	},
	"v3Migrator": {
		"address": "0x047fD82ADAaFDebfFBDE94493356BF85361B5180",
		"args": {
			"factory": "0xFB1370296ab08f5404653b57F845C73885574D63",
			"weth": "0x04E0459121DB7D49AE932428762a44B616E967D6",
			"nonfungiblePositionManager": "0x40A9776F35cfc9e02e6985b02b9586fE8357b369"
		}
	},
	"quoterV2": {
		"address": "0xFF3d4D112680Ea24866F1ba9B91bcBbB79c17BAD",
		"args": {
			"factory": "0xFB1370296ab08f5404653b57F845C73885574D63",
			"weth": "0x04E0459121DB7D49AE932428762a44B616E967D6"
		}
	},
	"swapRouter": {
		"address": "0x98fA55c53434A96b96aA96f0CF15C759d4FcD901",
		"args": {
			"factory": "0xFB1370296ab08f5404653b57F845C73885574D63",
			"weth": "0x04E0459121DB7D49AE932428762a44B616E967D6"
		}
	}
}
```



### base sepolia

```
{
	"weth": {
		"address": "0xb59f43AdC35FF42b8735F92e7edDa842b7C08206"
	},
	"uniswapV2Factory": {
		"address": "0xEcCAFd901A6A2DC4A5cbeA17C790B765821cCb72",
		"args": {
			"feeToSetter": "0x4408e1c6745B43350711317C89Db35B479992e5C"
		}
	},
	"uniswapV2Router": {
		"address": "0x5807f87541F90496bc74FC1de5139A4040a27DF9",
		"args": {
			"facotry": "0xEcCAFd901A6A2DC4A5cbeA17C790B765821cCb72",
			"weth": "0xb59f43AdC35FF42b8735F92e7edDa842b7C08206"
		}
	}
}
```





### Note

Dependencies that need to be replaced for deploying SwapRouter02

```
swap-router

SwapRouter02.sol 11line
import './base/ApproveAndCall.sol'; -> import {ApproveAndCall} from './base/ApproveAndCall.sol';

V3SwapRouter.sol 9-10 lines
import '@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol';
import '@uniswap/v3-periphery/contracts/libraries/CallbackValidation.sol';  -> 
import '../v3-periphery/libraries/PoolAddress.sol';
import '../v3-periphery/libraries/CallbackValidation.sol';

base/OracleSlippage.sol 10 line
import '@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol'; -> import '../../v3-periphery/libraries/PoolAddress.sol';
```

