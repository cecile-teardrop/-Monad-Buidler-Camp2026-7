# AI Agent Arena — Monad Buidler Camp Week 2

> 基于 Monad Testnet 的链上 AI Agent 竞技场，三合约架构：Agent NFT + 对战引擎 + 排行榜。

## 项目简介

这是一个链上 AI Agent 竞技场的核心合约系统。玩家铸造 Agent NFT，使用 Agent 参加对战，胜利获得经验和排行榜分数。所有对战过程上链，可验证、可审计。

### 核心理念

- **可验证的公平竞争** — 所有动作和结果都在链上，任何人可审计
- **Agent 成长系统** — NFT 有属性、等级、经验值，越战越强
- **任务驱动评分** — 分数不直接输入，通过完成里程碑任务间接获得

## 三合约架构

```
┌─────────────────────────────────────────────────────┐
│                   ScoreLeaderboard                   │
│   任务系统 + 分数累加 + 降序排行榜                     │
│                                                       │
│   接口: completeTask(user, taskId)  ← 被调用方        │
│         addVerifier(addr)            ← 授权 Arena     │
│         registerTask(name, points)   ← 注册里程碑     │
└──────────────────────┬──────────────────────────────┘
                       │ completeTask()
                       │
┌──────────────────────┼──────────────────────────────┐
│                    Arena (对战引擎)                    │
│   状态机 + 胜负判定 + NFT 经验 + 排行榜集成             │
│                                                       │
│   createBattle(maxRounds, nftId)                     │
│       → joinBattle(battleId, nftId)                  │
│       → submitMove(battleId, move) × N              │
│       → _endBattle()                                 │
│                                                       │
│   胜者 NFT +50 XP | 败者 +10 XP | 平局各 +20 XP      │
│   排行榜: Battle Win +5 | Draw +2 | 3连胜 +10        │
└──────────────────────┬──────────────────────────────┘
                       │ addExperience / recordBattle
                       │
┌──────────────────────▼──────────────────────────────┐
│                    AgentNFT                           │
│   ERC-721 + 5 属性 + 等级 + 经验值 + 升级              │
│                                                       │
│   属性: strength / speed / strategy / defense / luck  │
│   范围: 40-80 (Mint 时随机)                           │
│   升级: 每级随机 +1~+3 某项属性, 上限 100             │
└─────────────────────────────────────────────────────┘
```

### 合约清单

| 合约 | 文件 | 职责 | Bytecode |
|------|------|------|----------|
| ScoreLeaderboard | `ScoreLeaderboard.sol` | 任务系统 + 分数排行榜 | ~12K chars |
| AgentNFT | `AgentNFT.sol` | ERC-721 Agent NFT + 属性 + 升级 | 15410 chars |
| Arena | `Arena.sol` | 对战引擎 + 三合约集成 | 19806 chars |

## Agent 属性体系

| 属性 | 说明 | 范围 |
|------|------|------|
| Strength | 攻击力 — 影响攻击伤害 | 40-100 |
| Speed | 速度 — 影响出手顺序 / 闪避 | 40-100 |
| Strategy | 策略 — 影响暴击率 | 40-100 |
| Defense | 防御 — 减少受到的伤害 | 40-100 |
| Luck | 运气 — 随机增益 | 40-100 |

**升级机制：**
- Level 1 → 2：需要 100 XP
- Level N → N+1：需要 N × 100 XP
- 每次升级随机提升 1 项属性 +1~+3
- 对战胜利 +50 XP，失败 +10 XP，平局 +20 XP

## Remix 部署流程（推荐）

### 前置准备

1. 安装 MetaMask 浏览器插件
2. 在 MetaMask 添加 Monad Testnet 网络：
   - 网络名称：Monad Testnet
   - RPC URL：`https://testnet-rpc.monad.xyz`
   - 链 ID：`10143`
   - 货币符号：`MON`
   - 区块浏览器：`https://testnet.monadscan.com`
3. 获取测试币：前往 Monad Discord 领取测试 MON

### 部署步骤

> 在 Remix 中编译所有合约时，需要开启 **Enable optimization** 和 **viaIR**。
> Solidity Compiler → Advanced Configurations → 勾选 Enable optimization → 设置 viaIR: true

#### Step 1: 部署 ScoreLeaderboard

```
1. 打开 Remix (remix.ethereum.org)
2. 文件浏览器 → 新建文件 → ScoreLeaderboard.sol → 粘贴合约代码
3. Solidity Compiler → 编译器版本选 0.8.24+ → 编译
4. Deploy & Run → Environment 选 Injected Provider - MetaMask
5. 确认 MetaMask 连接到 Monad Testnet
6. 选择 ScoreLeaderboard 合约 → Deploy
7. 复制部署后的合约地址（记为 ADDR_LEADERBOARD）
```

#### Step 2: 部署 AgentNFT

```
1. 新建文件 → AgentNFT.sol → 粘贴合约代码 → 编译
2. Deploy 面板 → 选择 AgentNFT
3. 构造函数参数 mintPrice_ 填 0（免费 Mint）
4. Deploy
5. 复制部署后的合约地址（记为 ADDR_NFT）
```

#### Step 3: 部署 Arena

```
1. 新建文件 → Arena.sol → 粘贴合约代码 → 编译
2. Deploy 面板 → 选择 Arena
3. 构造函数参数:
   leaderboard_ = ADDR_LEADERBOARD
   agentNFT_    = ADDR_NFT
4. Deploy
5. 复制部署后的合约地址（记为 ADDR_ARENA）
```

#### Step 4: 初始化 Arena

```
1. 在 Arena 合约界面 → 找到 initialize() 函数 → 点击调用
2. 这会做 3 件事:
   - 在 ScoreLeaderboard 注册 4 个里程碑任务
   - 将 Arena 设为排行榜验证者
   - 触发 Initialized 事件
```

#### Step 5: 授权 Arena 调用 AgentNFT

```
1. 切换到 AgentNFT 合约界面
2. 找到 addAuthorizedContract(address) 函数
3. 参数填 ADDR_ARENA → 点击调用
4. 这允许 Arena 为 NFT 添加经验和记录对战
```

### 交互测试

#### Mint 两个 Agent NFT

```
# 账户 A Mint 第一个 Agent
AgentNFT.mintAgent("") → 返回 tokenId = 1
AgentNFT.getAgent(1) → 查看属性

# 账户 B Mint 第二个 Agent
AgentNFT.mintAgent("") → 返回 tokenId = 2
AgentNFT.getAgent(2) → 查看属性
```

#### 创建并完成一场对战

```
# 账户 A 创建对战（Best of 3，使用 NFT #1）
Arena.createBattle(3, 1) → battleId = 0

# 账户 B 加入对战（使用 NFT #2）
Arena.joinBattle(0, 2)

# 第 1 轮
Arena.submitMove(0, 1)  # A 出 Rock (账户A操作)
Arena.submitMove(0, 3)  # B 出 Scissors (账户B操作) → Rock beats Scissors → A 赢

# 第 2 轮
Arena.submitMove(0, 2)  # A 出 Paper
Arena.submitMove(0, 1)  # B 出 Rock → Paper beats Rock → A 赢

# A 2:0 获胜！
# - A 的 NFT #1 获得 50 XP
# - B 的 NFT #2 获得 10 XP
# - A 在排行榜获得 Battle Win 里程碑（+5 分）
```

#### 查询结果

```
# 查看对战结果
Arena.getBattle(0) → winner = 账户A, p1Score=2, p2Score=0

# 查看 NFT 成长
AgentNFT.getAgent(1) → experience=50, totalBattles=1, wins=1
AgentNFT.getLevel(1) → 1 (50/100 XP, 还需 50 XP 升级)

# 查看排行榜
ScoreLeaderboard.getScore(账户A) → 5
ScoreLeaderboard.getRank(账户A) → 1
```

## 函数速查

### ScoreLeaderboard

| 函数 | 类型 | 说明 |
|------|------|------|
| `completeTask(user, taskId)` | write | 标记任务完成（仅验证者） |
| `registerTask(name, points)` | write | 注册新任务（仅 Owner） |
| `addVerifier(addr)` | write | 添加验证者（仅 Owner） |
| `getScore(user)` | view | 查询用户总分 |
| `getRank(user)` | view | 查询用户排名 |
| `getLeaderboard()` | view | 获取完整排行榜 |
| `getTopN(n)` | view | 获取 Top N |

### AgentNFT

| 函数 | 类型 | 说明 |
|------|------|------|
| `mintAgent(uri)` | payable | 铸造新 Agent NFT |
| `getAgent(tokenId)` | view | 查询 Agent 完整属性 |
| `getTotalPower(tokenId)` | view | 查询战力总值（5 属性之和） |
| `getWinRate(tokenId)` | view | 查询胜率（万分比） |
| `addExperience(tokenId, exp)` | write | 添加经验（仅授权合约） |
| `recordBattle(tokenId, won)` | write | 记录对战（仅授权合约） |
| `tokensOfOwner(addr)` | view | 查询持有所有 NFT |

### Arena

| 函数 | 类型 | 说明 |
|------|------|------|
| `createBattle(maxRounds, nftId)` | payable | 创建对战（需持有 NFT） |
| `joinBattle(battleId, nftId)` | payable | 加入对战（需持有 NFT） |
| `submitMove(battleId, move)` | write | 提交动作 (1=Rock 2=Paper 3=Scissors) |
| `cancelBattle(battleId)` | write | 取消未开始的对战 |
| `getBattle(battleId)` | view | 查询对战信息 |
| `getBattleNFTLevels(battleId)` | view | 查询双方 NFT 等级 |
| `getPlayerStats(player)` | view | 查询玩家统计 |

## 编译信息

| 合约 | 编译器 | 优化器 | viaIR | Bytecode | 函数数 | 事件数 |
|------|--------|--------|-------|----------|--------|--------|
| ScoreLeaderboard | 0.8.28 | runs=200 | - | ~12K | 17 | 4 |
| AgentNFT | 0.8.28 | runs=200 | yes | 15410 | 32 | 9 |
| Arena | 0.8.28 | runs=200 | yes | 19806 | 26 | 7 |

## 里程碑任务

| 任务 | 分值 | 触发条件 |
|------|------|----------|
| Battle Win | 5 分 | 首次赢得对战 |
| Battle Draw | 2 分 | 首次平局 |
| Win Streak x3 | 10 分 | 首次 3 连胜 |
| First Agent Mint | 3 分 | 首次铸造 Agent NFT |

## AI 协作说明

| 任务 | AI 贡献 | 人工贡献 |
|------|---------|---------|
| 架构设计 | 三合约分离方案 | 确认属性体系和分值设计 |
| AgentNFT 编写 | ERC-721 完整实现 | 确认属性范围 40-80、升级公式 |
| Arena 集成 | NFT 经验值分配逻辑 | 确定 XP 数值 (50/10/20) |
| 编译修复 | — | viaIR 解决 Stack too deep |
| 安全审查 | try-catch 容错方案 | 确认授权合约机制 |

## 已知限制与 Week 3 方向

| # | 限制 | Week 3 方向 |
|---|------|-------------|
| 1 | submitMove 直接提交，可被前跑 | 实现 commit-reveal 两步提交 |
| 2 | 无超时机制 | 添加 timeoutBlocks 参数 |
| 3 | NFT 属性不影响 RPS 判定 | 扩展属性影响胜负的战斗公式 |
| 4 | 伪随机数依赖 blockhash | 集成 Chainlink VRF |
| 5 | 冒泡排序 O(n²) | 优化为链下排序 + 链上验证 |

## 安全提醒

- **不要提交私钥、助记词、API Key**
- **.env 文件已在 .gitignore 中排除**
- **部署使用 Remix + MetaMask，私钥不离开钱包**
- **区块浏览器：`https://testnet.monadscan.com`**

## License

MIT
