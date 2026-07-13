# ScoreLeaderboard — 基于任务认证的链上分数排行榜

> **Monad Buidler Camp · Mini Demo 0 · 方向：Tech**
>
>  2026-07-13

---

## 这是什么

一个部署在 Monad Testnet 上的智能合约，实现了**任务系统 + 分数累加 + 实时排行榜**。

用户不直接输入分数，而是通过完成预定义任务（1/2/3/5/7/10 分六个等级）间接获得分数。合约自动累加并维护降序排行榜，任何人都可以链上查询排名。

```
用户完成任务 → 验证者调用 completeTask(user, taskId) → 合约自动加分 → 排行榜实时更新
     │                                            │
     │  分值由合约定义，用户无法自行修改             │  任何人可查询，链上可验证
     └─────────────── 信任最小化 ──────────────────┘
```

---

## 任务分值体系

| 等级 | 分值 | 预定义任务 | 说明 |
|------|------|-----------|------|
| 入门 | 1 | Daily Check-in, Social Share | 每日参与 |
| 基础 | 2 | Quiz Bronze | 基础问答 |
| 进阶 | 3 | Quiz Silver | 进阶问答 |
| 中级 | 5 | Trade Novice, Community Build | 交易/社区 |
| 高级 | 7 | Quiz Gold, Trade Pro | 高难度 |
| 大师 | 10 | Trade Master, Bug Bounty | 最高分值 |



## 合约函数

  写入函数（消耗 Gas）

| 函数 | 权限 | 说明 |
|------|------|------|
| `completeTask(user, taskId)` | Verifier | 为用户标记任务完成，自动加分 |
| `batchCompleteTasks(users[], taskIds[])` | Verifier | 批量完成，节省 Gas |
| `registerTask(name, points)` | Owner | 注册新的自定义任务 |
| `addVerifier(addr)` / `removeVerifier(addr)` | Owner | 管理验证者 |

  查询函数（免费，不上链）

| 函数 | 返回 | 说明 |
|------|------|------|
| `getScore(user)` | uint256 | 用户总分 |
| `getRank(user)` | uint256 | 用户排名（1-indexed） |
| `getLeaderboard()` | (address[], uint256[]) | 完整排行榜（降序） |
| `getTopN(n)` | (address[], uint256[]) | Top N 排行榜 |
| `getUserSummary(user)` | (score, rank, taskCount, isRegistered) | 用户完整信息 |
| `getAllTasks()` | (ids[], names[], points[]) | 所有已注册任务 |
| `hasCompletedTask(user, taskId)` | bool | 用户是否完成某任务 |
| `getTotalParticipants()` | uint256 | 参与者总数 |



## 用 Remix IDE 部署（推荐，无需本地环境）

  第 1 步：打开 Remix

访问 [https://remix.ethereum.org](https://remix.ethereum.org)

  第 2 步：创建合约文件

1. 左侧 File Explorer → 点击 `contracts/` 文件夹
2. 新建文件 `ScoreLeaderboard.sol`
3. 将本仓库中的 `ScoreLeaderboard.sol` 内容粘贴进去

  第 3 步：编译

1. 左侧点击 Solidity Compiler 图标（S 形图标）
2. 编译器版本选择 `0.8.24` 或更高
3. 点击 **Compile ScoreLeaderboard.sol**
4. 编译成功后底部显示绿色 ✓

  第 4 步：配置 MetaMask

1. 打开 MetaMask → 点击网络选择器 → Add Network → Manual Entry
2. 填入：

| 字段 | 值 |
|------|-----|
| Network Name | Monad Testnet |
| RPC URL | `https://testnet-rpc.monad.xyz` |
| Chain ID | `10143` |
| Currency Symbol | `MON` |
| Block Explorer | `https://testnet.monadscan.com` |

3. 从 [Monad Faucet](https://faucet.monad.xyz) 领取测试币

  第 5 步：部署

1. 左侧点击 Deploy & Run Transactions 图标
2. **Environment** 选择 `Injected Provider - MetaMask`
3. MetaMask 弹出 → 确认连接 → 确保切换到 Monad Testnet
4. Contract 下拉选择 `ScoreLeaderboard`
5. 点击 **Deploy**
6. MetaMask 弹出签名 → 确认
7. 部署成功后，底部出现合约地址（绿色 ✓）

  第 6 步：交互测试

部署成功后，Remix 左下方会展开合约的所有函数：

**测试完成任务（Write）：**

1. 找到 `completeTask` 函数
2. 输入参数：
   - `user`: 填一个测试地址，如 `0xA1ce1B3369BFC1e3D1a4f3E5b7C9d1E2f3A4b5C6`
   - `taskId`: 填 `0`（Daily Check-in，1 分）
3. 点击 transact → MetaMask 确认 → 等待上链

**查询分数（Read）：**

1. 找到 `getScore` 函数
2. 输入刚才的用户地址
3. 点击 call → 返回 `1`

**查看排行榜（Read）：**

1. 找到 `getLeaderboard` 函数
2. 点击 call → 返回排序后的地址数组和分数数组

**验证防重复：**

1. 再次调用 `completeTask` 填入相同的用户和 `taskId: 0`
2. 交易会 revert，报错 `task already completed`

  第 7 步：区块浏览器验证

打开 [https://testnet.monadscan.com](https://testnet.monadscan.com)

- 输入合约地址 → 查看合约代码和交易历史
- 输入交易 Hash → 查看交易状态（status: 1 = 成功）
- 在 Events 标签页可以看到 `TaskCompleted` 事件



## 交互演示示例

模拟 4 个用户完成不同任务：

| 用户 | 完成的任务 | 计算 | 总分 | 排名 |
|------|-----------|------|------|------|
| Alice | Daily Check-in(1) + Quiz Silver(3) | 1+3 | 4 | #4 |
| Bob | Trade Novice(5) + Quiz Gold(7) | 5+7 | 12 | #1 |
| Carol | Bug Bounty(10) | 10 | 10 | #3 |
| Dave | Social Share(1) + Trade Master(10) | 1+10 | 11 | #2 |

调用 `getLeaderboard()` 返回（降序）：


#1  Bob    12 pts
#2  Dave   11 pts
#3  Carol  10 pts
#4  Alice   4 pts




## 哪部分是真实链上操作

| 操作 | 链上？ | 说明 |
|------|--------|------|
| 合约部署 | ✅ | 交易广播到 Monad Testnet |
| `completeTask` 调用 | ✅ | 写操作，修改链上状态，消耗 Gas |
| `getLeaderboard` 查询 | ✅ | 链上计算排序，结果可验证 |
| `getRank` 查询 | ✅ | 链上遍历计算排名 |
| 模拟用户地址 | ❌ | 演示用硬编码地址，实际用真实钱包 |


## AI 辅助 vs 人工判断

| 任务 | AI 贡献 | 人工贡献 |
|------|---------|---------|
| 合约设计 | 建议存储结构 | 确定六级分值体系（1/2/3/5/7/10） |
| 合约代码 | 生成 Solidity | 修复 NatSpec 编译错误（`taskIds` → `taskIds_`） |
| 部署方式 | 提供脚本方案 | 改用 Remix + MetaMask（私钥不离开钱包） |
| 任务分值 | 建议 4 级 | 扩展为 6 级，更贴近游戏化设计 |
| 排行榜算法 | 冒泡排序 | 判断演示场景够用，未过度优化 |



## 方向选择：Tech

  为什么选 Tech

1. **已有完整开发实践**：从 SimpleStorage 到 ScoreLeaderboard，每一步都亲手操作
2. **兴趣驱动**：部署合约在区块浏览器看到 `status: 1` 的成就感是核心驱动力
3. **技能匹配**：有编程基础，对状态管理、权限模型理解较快
4. **Week 2 有技术纵深**：AI Agent 竞技场需要 5 个核心合约，可逐个实现

  Tech / Ops / Research 对比

| 方向 | 含义 | 产出物 |
|------|------|--------|
| **Tech** ✅ | 合约开发、DApp 构建、工具链 | 可运行的合约 + DApp |
| Ops | 社区增长、活动运营、Meme | 用户增长 + 活跃 |
| Research | 生态研究、竞品分析、建模 | 研究报告 |



## 简历一句话

> 设计并实现了基于任务认证的链上分数排行榜智能合约，支持六级分值体系、批量任务完成、实时排名查询和 Top N 排行榜，部署于 Monad Testnet，验证了高吞吐区块链在游戏化任务激励系统中的应用可行性。



## Week 2 推进方向

1. **BattleEngine 核心合约**：从伪代码推进到可部署的 Solidity 实现
2. **AgentNFT (ERC-721)**：Agent 铸造功能，与排行榜集成
3. **前端对战画面**：监听链上事件，实时渲染排行榜

  需要助教或同伴帮助的问题

1. **Monad 并行执行**：两个 `completeTask` 同时执行是否需要并发控制？
2. **Foundry vs Hardhat**：多合约系统选哪个？Monad Testnet 配置有坑吗？
3. **链上事件 → 前端**：400ms 出块下直接监听 RPC event 够用吗？
4. **排行榜 Gas 优化**：冒泡排序 O(n²) 大规模时怎么优化？



## 文件结构

```
├── ScoreLeaderboard.sol    # 合约源码（粘贴到 Remix 编译部署）
├── README.md               # 本文件
└── demo.html               # HTML 演示文档（可用 GitHub Pages 托管）
```



## 技术栈

| 项目 | 值 |
|------|-----|
| 合约语言 | Solidity ^0.8.24 |
| 部署工具 | Remix IDE + MetaMask |
| 网络 | Monad Testnet (Chain ID: 10143) |
| 区块浏览器 | https://testnet.monadscan.com |
| 水龙头 | https://faucet.monad.xyz |


> **Mini Demo 0 · 2026-07-13 · 方向：Tech**
