// SPDX-License-Identifier: MIT
pragma solidity >=0.4.0 <0.8.0;

/// @title 512 位精度数学函数
/// @notice 在不损失精度的情况下完成可能产生 256 位中间溢出的乘除运算
/// @dev 处理“幻影溢出”：`a * b` 可能超过 uint256，但 `(a * b) / denominator` 最终仍可放入 uint256。
/// 这在价格、流动性和 Q96/Q128 缩放值相乘时非常常见。若先做普通乘法会错误回退或截断；
/// 本库保留乘积高低共 512 位，再执行精确除法，并提供明确的向下或向上取整版本。
library FullMath {
    /// @notice 以完整精度计算 floor(a×b÷denominator)
    /// @dev 结果超过 uint256 或 denominator 为 0 时回退。算法由 Remco Bloemen 以 MIT 许可发布：
    /// https://xn--2-umb.com/21/muldiv
    /// @param a 被乘数
    /// @param b 乘数
    /// @param denominator 除数
    /// @return result 256 位计算结果
    function mulDiv(
        uint256 a,
        uint256 b,
        uint256 denominator
    ) internal pure returns (uint256 result) {
        // 计算 512 位乘积 [prod1 prod0] = a * b。
        // 分别求乘积模 2**256 和模 2**256 - 1 的结果，再用中国剩余定理重建：
        // product = prod1 * 2**256 + prod0。
        uint256 prod0; // 乘积的低 256 位
        uint256 prod1; // 乘积的高 256 位
        assembly {
            let mm := mulmod(a, b, not(0))
            prod0 := mul(a, b)
            prod1 := sub(sub(mm, prod0), lt(mm, prod0))
        }

        // 高 256 位为 0 时没有中间溢出，直接执行普通 256 位除法
        if (prod1 == 0) {
            require(denominator > 0);
            assembly {
                result := div(prod0, denominator)
            }
            return result;
        }

        // denominator 必须大于高位部分，才能保证最终结果小于 2**256；同时排除除数为 0
        require(denominator > prod1);

        ///////////////////////////////////////////////
        // 512 位数除以 256 位数
        ///////////////////////////////////////////////

        // 从 512 位乘积中减去余数，把后续除法转换为整除；余数通过 mulmod 计算
        uint256 remainder;
        assembly {
            remainder := mulmod(a, b, denominator)
        }
        // 从 512 位数中减去一个 256 位余数，并处理低位借位
        assembly {
            prod1 := sub(prod1, gt(remainder, prod0))
            prod0 := sub(prod0, remainder)
        }

        // 提取 denominator 中最大的 2 的幂因子，该值始终大于或等于 1
        uint256 twos = -denominator & denominator;
        // 除去 denominator 中的 2 的幂，使其变为奇数并可在模 2**256 下求逆
        assembly {
            denominator := div(denominator, twos)
        }

        // 同步将 512 位被除数除以该 2 的幂因子
        assembly {
            prod0 := div(prod0, twos)
        }
        // 把 prod1 的有效位移入 prod0。先把 twos 转换为 2**256 / twos；
        // 在 uint256 回绕语义下，twos 为 1 时转换结果仍为 1
        assembly {
            twos := add(div(sub(0, twos), twos), 1)
        }
        prod0 |= prod1 * twos;

        // denominator 已为奇数，因此存在模 2**256 的乘法逆元：
        // denominator * inv = 1 mod 2**256。先构造在低 4 位上正确的初始值
        uint256 inv = (3 * denominator) ^ 2;
        // 使用牛顿-拉夫森迭代提升精度。根据 Hensel 引理，每轮将正确位数翻倍
        inv *= 2 - denominator * inv; // 模 2**8 的逆元
        inv *= 2 - denominator * inv; // 模 2**16 的逆元
        inv *= 2 - denominator * inv; // 模 2**32 的逆元
        inv *= 2 - denominator * inv; // 模 2**64 的逆元
        inv *= 2 - denominator * inv; // 模 2**128 的逆元
        inv *= 2 - denominator * inv; // 模 2**256 的逆元

        // 当前除法已保证整除，因此乘以 denominator 的模逆元即可得到模 2**256 的商。
        // 前置条件保证真实结果小于 2**256，所以该低 256 位结果就是最终答案，无需再计算高位
        result = prod0 * inv;
        return result;
    }

    /// @notice 以完整精度计算 ceil(a×b÷denominator)
    /// @dev 先向下取整；若存在余数则加 1。结果超过 uint256 或 denominator 为 0 时回退
    /// @param a 被乘数
    /// @param b 乘数
    /// @param denominator 除数
    /// @return result 256 位计算结果
    function mulDivRoundingUp(
        uint256 a,
        uint256 b,
        uint256 denominator
    ) internal pure returns (uint256 result) {
        result = mulDiv(a, b, denominator);
        if (mulmod(a, b, denominator) > 0) {
            require(result < type(uint256).max);
            result++;
        }
    }
}
