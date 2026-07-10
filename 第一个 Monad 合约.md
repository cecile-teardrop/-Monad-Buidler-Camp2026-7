# Monad Mini Contract — SimpleStorage

> Monad Buidler Camp 任务：将第一个最小合约部署到 Monad Testnet，并完成至少一次合约交互。

## 合约简介

**SimpleStorage** 是一个极简的链上存储合约，核心功能：

| 功能 | 函数 | 类型 | 说明 |
|------|------|------|------|
| 设置值 | `set(uint256 _value)` | write | 更新链上存储的值，触发 `ValueChanged` 事件 |
| 读取值 | `get()` | read | 返回当前存储的值 |
| 查询部署者 | `getOwner()` | read | 返回合约部署者地址 |

### 合约源码

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract SimpleStorage {
    uint256 private storedValue;
    address public owner;

    event ValueChanged(uint256 oldValue, uint256 newValue, address changedBy);

    constructor() {
        owner = msg.sender;
        storedValue = 0;
    }

    function set(uint256 _value) public {
        uint256 oldValue = storedValue;
        storedValue = _value;
        emit ValueChanged(oldValue, _value, msg.sender);
    }

    function get() public view returns (uint256) {
        return storedValue;
    }

    function getOwner() public view returns (address) {
        return owner;
    }
}
```

## Monad Testnet 网络信息

| 参数 | 值 |
|------|-----|
| 网络名称 | Monad Testnet |
| Chain ID | `10143` |
| RPC URL | `https://testnet-rpc.monad.xyz` |
| 货币符号 | `MON` |
| 区块浏览器 | [https://testnet.monadscan.com](https://testnet.monadscan.com) |
| 水龙头 | [https://faucet.monad.xyz](https://faucet.monad.xyz) |

## 部署步骤（Remix + MetaMask）

### 1. 添加 Monad Testnet 到 MetaMask

打开 MetaMask → 设置 → 网络 → 添加网络 → 手动填写：

| 字段 | 填入内容 |
|------|----------|
| 网络名称 | `Monad Testnet` |
| RPC URL | `https://testnet-rpc.monad.xyz` |
| Chain ID | `10143` |
| 货币符号 | `MON` |
| 区块浏览器 | `https://testnet.monadscan.com` |

保存并切换到 Monad Testnet 网络。

> 也可以用 [Chainlist](https://chainlist.org/chain/10143) 一键添加。

### 2. 领取测试币

前往 [https://faucet.monad.xyz](https://faucet.monad.xyz)，输入钱包地址领取测试网 MON。

### 3. 编译合约

1. 打开 [Remix IDE](https://remix.ethereum.org)
2. 新建文件 `SimpleStorage.sol`，粘贴上方合约源码
3. 左侧点击 **Solidity Compiler**
4. 编译器版本选择 `0.8.24` 或更高
5. 点击 **Compile SimpleStorage.sol**

### 4. 部署合约

1. 左侧点击 **Deploy & Run Transactions**
2. **Environment** 下拉选择 **Injected Provider - MetaMask**
3. MetaMask 弹窗 → 连接账户 → 确认切换到 Monad Testnet
4. **Contract** 下拉选择 `SimpleStorage`
5. 点击橙色 **Deploy** 按钮
6. MetaMask 弹窗 → 确认交易
7. 终端显示 `status: 1 Transaction mined` 表示部署成功

部署成功后：
- **Deployed Contracts** 区域显示合约地址
- 终端输出中 `contract address` 和 `transaction hash` 即部署信息

## 交互步骤

在 Remix 左侧 **Deployed Contracts** 中展开合约，可见函数按钮列表：

### Read 调用

1. 点击 **get** → 返回当前存储值（初始为 `0`）
2. 点击 **getOwner** → 返回合约部署者地址

> Read 调用不上链、不花 gas，即时返回结果。

### Write 调用

1. 在 **set** 旁的输入框填入 `42`
2. 点击橙色 **set** 按钮
3. MetaMask 弹窗 → 确认交易
4. 终端显示交易 hash 和 `status: 1` 表示成功

### 验证

再次点击 **get** → 返回值变为 `42`，确认 write 调用已生效。

## 部署记录

> 本合约在 Monad Testnet 上的实际部署信息

| 项目 | 值 |
|------|-----|
| 合约地址 | `0x864eD8d14e58d77d081C1CDC54478CB32019954e` |
| 部署交易 Hash | `0xdf09964ca94f35ebae190216b2a683f20269e6943cb77152c2e5d19f49f4160d` |
| 交互交易 Hash (set) | `0xfc88e7a6181999abc6b535acfe76989f7081f2ad3346656b12420a96e4ae2486` |
| 部署者地址 | `0x6A804B989AAfb5206BBDbE708CB31Ee60b7297Dd` |
| 部署区块 | `43682463` |
| 部署时间 | 2026-07-10 |
| 网络 | Monad Testnet (Chain ID: 10143) |
| 部署工具 | Remix IDE + MetaMask |

### 区块浏览器验证

- 合约地址：[查看合约](https://testnet.monadscan.com/address/0x864eD8d14e58d77d081C1CDC54478CB32019954e)
- 部署交易：[查看 Tx](https://testnet.monadscan.com/tx/0xdf09964ca94f35ebae190216b2a683f20269e6943cb77152c2e5d19f49f4160d)
- 交互交易：[查看 Tx](https://testnet.monadscan.com/tx/0xfc88e7a6181999abc6b535acfe76989f7081f2ad3346656b12420a96e4ae2486)

## 完整链路说明

```
合约源码 (.sol)
    │
    ▼
  Remix 编译 (solc)  →  ABI + Bytecode
    │
    ▼
  MetaMask 签名部署 (Injected Provider)  →  合约地址 + 部署 TX Hash
    │
    ▼
  read 调用 (get / getOwner)  →  读取链上状态，不上链不花 gas
    │
    ▼
  write 调用 (set(42))  →  修改链上状态 + 交互 TX Hash
    │
    ▼
  区块浏览器验证 (MonadScan)  →  查看交易、事件、合约状态
```


