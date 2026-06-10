// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * @title Solidity bytes 数组工具
 * @author Gonçalo Sá <goncalo.sa@consensys.net>
 *
 * @dev 面向 Solidity 的紧凑 bytes 数组工具库，支持拼接、切片和类型转换。
 *      V3 Path 使用它从紧凑 calldata 中读取 20 字节 token 地址和 3 字节 fee。
 *      汇编代码手动维护内存长度、对齐和 free-memory pointer；调用方必须先保证切片边界有效。
 */
pragma solidity >=0.5.0 <0.8.0;

library BytesLib {
    function slice(
        bytes memory _bytes,
        uint256 _start,
        uint256 _length
    ) internal pure returns (bytes memory) {
        require(_length + 31 >= _length, 'slice_overflow');
        require(_start + _length >= _start, 'slice_overflow');
        require(_bytes.length >= _start + _length, 'slice_outOfBounds');

        bytes memory tempBytes;

        assembly {
            switch iszero(_length)
                case 0 {
                    // 获取空闲内存位置，并按照 Solidity 创建内存变量的方式赋给 tempBytes
                    tempBytes := mload(0x40)

                    // 切片结果的第一个 word 可能来自原数组中的非对齐部分。
                    // 先计算该部分长度，再从对应偏移开始按 32 字节复制。
                    // 首次复制的高位可能包含无关数据，但末尾 lengthmod 字节会准确落到新数组内容起点。
                    // 复制完成后，再用切片真实长度覆盖新数组的第一个完整 word
                    let lengthmod := and(_length, 31)

                    // 下一行乘法用于处理长度恰好为 32 字节倍数的情况。
                    // 若 lengthmod == 0 而不修正，复制循环会误把原数组长度当作数据复制并提前结束
                    let mc := add(add(tempBytes, lengthmod), mul(0x20, iszero(lengthmod)))
                    let end := add(mc, _length)

                    for {
                        // 下一行乘法与上面的修正用途相同
                        let cc := add(add(add(_bytes, lengthmod), mul(0x20, iszero(lengthmod))), _start)
                    } lt(mc, end) {
                        mc := add(mc, 0x20)
                        cc := add(cc, 0x20)
                    } {
                        mstore(mc, mload(cc))
                    }

                    mstore(tempBytes, _length)

                    // 更新空闲内存指针，并像编译器一样把数组分配长度向上补齐到 32 字节
                    mstore(0x40, and(add(mc, 31), not(31)))
                }
                // 请求零长度切片时直接返回空 bytes 数组
                default {
                    tempBytes := mload(0x40)
                    // 将即将返回的 32 字节内存清零，因为 Solidity 不会自动回收和清理旧内存
                    mstore(tempBytes, 0)

                    mstore(0x40, add(tempBytes, 0x20))
                }
        }

        return tempBytes;
    }

    function toAddress(bytes memory _bytes, uint256 _start) internal pure returns (address) {
        require(_start + 20 >= _start, 'toAddress_overflow');
        require(_bytes.length >= _start + 20, 'toAddress_outOfBounds');
        address tempAddress;

        assembly {
            tempAddress := div(mload(add(add(_bytes, 0x20), _start)), 0x1000000000000000000000000)
        }

        return tempAddress;
    }

    function toUint24(bytes memory _bytes, uint256 _start) internal pure returns (uint24) {
        require(_start + 3 >= _start, 'toUint24_overflow');
        require(_bytes.length >= _start + 3, 'toUint24_outOfBounds');
        uint24 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x3), _start))
        }

        return tempUint;
    }
}
