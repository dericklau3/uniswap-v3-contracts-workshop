// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

/// @title 禁止 delegatecall 进入合约
/// @notice 给子合约提供 noDelegateCall 修饰器，防止关键函数在代理上下文里执行。
/// @dev `delegatecall` 会执行目标合约代码，却读写调用方的存储，并让代码中的 `address(this)`
/// 变成调用方地址。V3 Pool 的余额校验、工厂身份和不可变参数都假设代码运行在真实池地址上；
/// 若允许代理借用这些函数，代码看到的 token 余额和状态槽就可能不再属于原池。
///
/// 部署时保存真实地址 `original`，运行时比较 `address(this)`。普通 call 两者相等；
/// delegatecall 时 `address(this)` 是代理地址，因此立即回退。它保护的是执行上下文，而不是用户权限。
abstract contract NoDelegateCall {
    /// @dev 合约部署后的原始地址，用来和运行时 address(this) 对比。
    address private immutable original;

    constructor() {
        // immutable 在 init code 中计算，并内联进最终字节码；运行时检查时这个值不会变化。
        original = address(this);
    }

    /// @dev 单独抽成 private 函数，避免修饰器被复制到每个函数时重复嵌入 immutable 地址字节。
    function checkNotDelegateCall() private view {
        require(address(this) == original);
    }

    /// @notice 阻止通过 delegatecall 调用被修饰的函数。
    modifier noDelegateCall() {
        checkNotDelegateCall();
        _;
    }
}
