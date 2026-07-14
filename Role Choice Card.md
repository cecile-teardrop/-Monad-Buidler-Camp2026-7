# Role Choice Card — 方向选择卡

> Monad Buidler Camp · 2026-07-13

---


选择方向：DEV
理由
| # | 理由 | 证据 |
|---|------|------|
| 1 | **已有完整开发链路经验** | 从 SimpleStorage（set/get/getOwner）到 ScoreLeaderboard（任务系统 + 排行榜 + 权限 + 批量），已完成编写 → 编译 → 部署 → 交互 → 验证全流程 |
| 2 | **兴趣驱动验证通过** | 在 Build Log 中明确写道："亲手部署合约并在区块浏览器看到 `status: 1` 的成就感是核心驱动力" |
| 3 | **技能匹配** | 有编程基础，对状态管理、权限模型、事件机制理解较快；Week 1 修复了 NatSpec 编译错误（`taskIds` → `taskIds_`），说明具备 debug 能力 |
| 4 | **方案已有技术纵深** | AI Agent 竞技场设计了 5 个核心合约（AgentNFT / ArenaRegistry / BattleEngine / Leaderboard / RewardPool），Week 2 可逐个推进 |
| 5 | **Research 能力作为辅助而非主方向** | Week 1 完成了 9 方向高频交互分析和 AI Agent 安全思考，证明有研究能力，但更希望"将研究转化为可运行的产品" |



## 服务的问题

> **核心问题：如何在 Monad 上实现"可验证的公平竞技"？**

### 问题拆解

```
AI Agent 竞技场的信任问题
  │
  ├── Agent 的决策逻辑能否被验证？    → 链下推理 + 链上提交架构
  ├── 对战过程是否公平？              → 链上 BattleEngine 强制规则
  ├── 排行榜是否可信？                → 链上分数累加 + 排序，任何人可审计
  └── 奖励分配是否透明？              → 链上 RewardPool 自动分发
```

### Dev 方向解决其中哪些

| 子问题 | Dev 产出 | Week 2 进度 |
|--------|----------|-------------|
| 对战过程公平 | BattleEngine 合约 | 伪代码 → 可部署 Solidity |
| 排行榜可信 | ScoreLeaderboard（已完成） | ✅ Week 1 已实现 |
| Agent 身份可验证 | AgentNFT (ERC-721) | 设计中 → Week 2 实现 |
| 奖励透明 | RewardPool 合约 | Week 3 规划 |

---

## 本周最小产出（Week 2）

### 必须完成（MVP）

| # | 产出 | 验收标准 |
|---|------|----------|
| 1 | **BattleEngine 合约** | 可编译、可部署，包含 `submitMove` → 状态更新 → 胜负判定的完整对战循环 |
| 2 | **Monad Testnet 部署** | 合约部署成功，区块浏览器可查，至少完成 1 场对战交互 |
| 3 | **GitHub 提交** | 合约源码 + README + 部署记录，README 含 Remix 部署步骤 |

### 加分项（如时间允许）

| # | 产出 | 验收标准 |
|---|------|----------|
| 4 | AgentNFT (ERC-721) | 基础铸造功能，与 BattleEngine 集成 |
| 5 | 前端对战画面 | 监听 `MoveExecuted` 事件，实时渲染排行榜 |
| 6 | BattleEngine 测试用例 | 至少覆盖正常对战、非法操作、平局 3 种场景 |



参考资料

### Monad 官方

| 资料 | 链接 | 用途 |
|------|------|------|
| Monad 官方文档 | https://docs.monad.xyz | RPC、Chain ID、工具配置 |
| Monad Testnet 浏览器 | https://testnet.monadscan.com | 合约验证、交易查询 |
| Monad Faucet | https://faucet.monad.xyz | 领取测试币 |
| Monad GitHub | https://github.com/monad-labs | 官方代码仓库 |

### Solidity / 合约开发

| 资料 | 链接 | 用途 |
|------|------|------|
| Solidity 官方文档 | https://docs.soliditylang.org | 语法、最佳实践 |
| Remix IDE | https://remix.ethereum.org | 在线编译部署（Week 1 已用） |
| OpenZeppelin Contracts | https://docs.openzeppelin.com/contracts | ERC-721、安全库 |
| Foundry Book | https://book.getfoundry.sh | 多合约工程化（备选工具链） |

### 竞品 / 参考

| 资料 | 用途 |
|------|------|
| EVM 并行执行模型（Monad） | 理解并行执行对合约状态依赖的影响 |
| AI Agent Arena 类项目调研 | 参考已有方案的架构设计 |

### Week 1 自有产出

| 资料 | 文件 |
|------|------|
| Week 1 Build Log | `Week1-Build-Log.md` |
| 高频交互笔记 | `Monad高频交互笔记.md` |
| AI Agent 竞技场方案 | `Monad高频交互应用方案.md` |
| AI Agent 安全思考 | `AI_Agent安全思考.md` |
| ScoreLeaderboard 合约 | `github-ready/ScoreLeaderboard.sol` |

---

Week 3 角色

### 角色：开发者（Developer）

| 维度 | 说明 |
|------|------|
| **角色名称** | Dev / Developer |
| **核心职责** | 把 AI Agent 竞技场从"合约能跑"推进到"DApp 可用" |
| **Week 3 预期产出** | 前端界面 + 合约集成 + 完整对战流程演示 |
| **协作需求** | 需要 Research 提供"AI Agent 链下推理可验证架构"的研究结论；需要 Ops 帮助设计任务激励活动 |




