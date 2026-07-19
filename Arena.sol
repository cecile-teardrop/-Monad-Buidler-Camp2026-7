// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Arena
 * @dev  Monad Buidler Camp — Week 2 Day 6
 *       AI Agent 竞技场 — 三合约集成版（ScoreLeaderboard + AgentNFT + BattleEngine）
 *
 * 架构：
 *   ┌──────────────────────────────────────────────────┐
 *   │               ScoreLeaderboard                   │
 *   │   (任务系统 + 分数累加 + 排行榜)                   │
 *   └────────────────────┬─────────────────────────────┘
 *                        │ completeTask()
 *   ┌────────────────────┼─────────────────────────────┐
 *   │                Arena (本合约)                      │
 *   │   (对战引擎 + NFT 集成 + 排行榜集成)                │
 *   │                                                   │
 *   │   createBattle(tokenId) → joinBattle(tokenId)     │
 *   │       → submitMove() × N → _endBattle()           │
 *   │   → 胜者 NFT 获得 50 XP，败者 10 XP               │
 *   │   → 排行榜里程碑任务更新                            │
 *   └────────────────────┬─────────────────────────────┘
 *                        │ addExperience / recordBattle
 *   ┌────────────────────▼─────────────────────────────┐
 *   │                  AgentNFT                         │
 *   │   (ERC-721 + 5 属性 + 升级 + 经验值)              │
 *   └──────────────────────────────────────────────────┘
 *
 * 与原版 BattleEngine 的区别：
 *   1. 玩家必须持有 Agent NFT 才能创建/加入对战
 *   2. 每场对战绑定双方 NFT，对战结果影响 NFT 成长
 *   3. 胜者 NFT +50 XP，败者 +10 XP，平局双方各 +20 XP
 *   4. NFT 属性不影响当前 RPS 判定（Week 3 扩展方向）
 */

// ============================================================
//  接口 — 只声明需要调用的函数
// ============================================================

interface IScoreLeaderboard {
    function completeTask(address user, uint256 taskId) external;
    function addVerifier(address verifier) external;
    function registerTask(string memory name, uint256 points) external returns (uint256);
}

interface IAgentNFT {
    function ownerOf(uint256 tokenId) external view returns (address);
    function addExperience(uint256 tokenId, uint256 exp) external;
    function recordBattle(uint256 tokenId, bool won) external;
    function getLevel(uint256 tokenId) external view returns (uint256);
}

// ============================================================
//  主合约
// ============================================================

contract Arena {

    // ============================================================
    //  枚举
    // ============================================================

    enum BattleState { Waiting, InProgress, Finished }
    enum MoveType { None, Rock, Paper, Scissors }
    enum RoundResult { Pending, Draw, Player1Win, Player2Win }

    // ============================================================
    //  结构体
    // ============================================================

    struct Battle {
        address player1;
        address player2;
        uint256 nftId1;          // P1 使用的 Agent NFT
        uint256 nftId2;          // P2 使用的 Agent NFT
        uint256 stake;
        BattleState state;
        uint256 maxRounds;
        uint256 winsNeeded;
        uint256 currentRound;
        uint256 p1Score;
        uint256 p2Score;
        address winner;
        address loser;
        bool isDraw;
        uint256 createdAt;
        uint256 endedAt;
    }

    struct Round {
        MoveType p1Move;
        MoveType p2Move;
        RoundResult result;
        bool p1Submitted;
        bool p2Submitted;
    }

    struct PlayerStats {
        uint256 wins;
        uint256 losses;
        uint256 draws;
        uint256 currentStreak;
        uint256 bestStreak;
        uint256 totalBattles;
    }

    // ============================================================
    //  常量 — 经验值奖励
    // ============================================================

    /// @dev 胜利获得的经验值
    uint256 public constant XP_WIN   = 50;
    /// @dev 失败获得的经验值（参与奖）
    uint256 public constant XP_LOSS  = 10;
    /// @dev 平局获得的经验值
    uint256 public constant XP_DRAW  = 20;

    // ============================================================
    //  存储
    // ============================================================

    IScoreLeaderboard public leaderboard;
    IAgentNFT public agentNFT;
    address public owner;

    Battle[] public battles;
    mapping(uint256 => mapping(uint256 => Round)) public rounds;
    mapping(address => PlayerStats) public playerStats;

    bool public initialized;

    // 里程碑任务 ID
    uint256 public taskBattleWin;
    uint256 public taskBattleDraw;
    uint256 public taskWinStreak3;
    uint256 public taskFirstAgentMint;

    // ============================================================
    //  事件
    // ============================================================

    event BattleCreated(
        uint256 indexed battleId,
        address indexed player1,
        uint256 indexed nftId1,
        uint256 stake,
        uint256 maxRounds
    );

    event BattleStarted(
        uint256 indexed battleId,
        address indexed player1,
        address indexed player2,
        uint256 nftId1,
        uint256 nftId2,
        uint256 maxRounds,
        uint256 timestamp
    );

    event MoveExecuted(
        uint256 indexed battleId,
        uint256 indexed round,
        address indexed player,
        MoveType move,
        uint256 timestamp
    );

    event RoundResolved(
        uint256 indexed battleId,
        uint256 indexed round,
        MoveType p1Move,
        MoveType p2Move,
        RoundResult result,
        uint256 p1Score,
        uint256 p2Score
    );

    event BattleEnded(
        uint256 indexed battleId,
        address winner,
        address loser,
        bool isDraw,
        uint256 p1Score,
        uint256 p2Score,
        uint256 winnerNftId,
        uint256 loserNftId,
        uint256 timestamp
    );

    event BattleCancelled(uint256 indexed battleId, address indexed creator);

    event Initialized(
        address leaderboard,
        address agentNFT,
        uint256 taskWin,
        uint256 taskDraw,
        uint256 taskStreak,
        uint256 taskMint
    );

    // ============================================================
    //  修饰符
    // ============================================================

    modifier onlyOwner() {
        require(msg.sender == owner, "Arena: not owner");
        _;
    }

    modifier notInitialized() {
        require(!initialized, "Arena: already initialized");
        _;
    }

    // ============================================================
    //  构造函数
    // ============================================================

    /// @param leaderboard_ ScoreLeaderboard 合约地址
    /// @param agentNFT_    AgentNFT 合约地址
    constructor(address leaderboard_, address agentNFT_) {
        owner = msg.sender;
        leaderboard = IScoreLeaderboard(leaderboard_);
        agentNFT = IAgentNFT(agentNFT_);
    }

    /// @notice 初始化 — 注册里程碑任务 + 授权
    function initialize() external onlyOwner notInitialized {
        taskBattleWin    = leaderboard.registerTask("Battle Win",     5);
        taskBattleDraw   = leaderboard.registerTask("Battle Draw",    2);
        taskWinStreak3   = leaderboard.registerTask("Win Streak x3", 10);
        taskFirstAgentMint = leaderboard.registerTask("First Agent Mint", 3);

        try leaderboard.addVerifier(address(this)) {} catch {}

        initialized = true;

        emit Initialized(
            address(leaderboard),
            address(agentNFT),
            taskBattleWin,
            taskBattleDraw,
            taskWinStreak3,
            taskFirstAgentMint
        );
    }

    // ============================================================
    //  核心逻辑 — 对战生命周期
    // ============================================================

    // ---------- 创建对战 ----------

    /// @notice 创建一场新对战（必须持有 Agent NFT）
    /// @param maxRounds 最大轮数（奇数：1/3/5/7/9）
    /// @param nftId     玩家1使用的 Agent NFT ID
    /// @return battleId 对战 ID
    function createBattle(uint256 maxRounds, uint256 nftId)
        external
        payable
        returns (uint256)
    {
        require(maxRounds % 2 == 1, "Arena: maxRounds must be odd");
        require(maxRounds >= 1 && maxRounds <= 9, "Arena: maxRounds 1-9");
        require(agentNFT.ownerOf(nftId) == msg.sender, "Arena: not your NFT");

        uint256 battleId = battles.length;

        battles.push(Battle({
            player1:      msg.sender,
            player2:      address(0),
            nftId1:       nftId,
            nftId2:       0,
            stake:        msg.value,
            state:        BattleState.Waiting,
            maxRounds:    maxRounds,
            winsNeeded:   (maxRounds / 2) + 1,
            currentRound: 0,
            p1Score:      0,
            p2Score:      0,
            winner:       address(0),
            loser:        address(0),
            isDraw:       false,
            createdAt:    block.timestamp,
            endedAt:      0
        }));

        emit BattleCreated(battleId, msg.sender, nftId, msg.value, maxRounds);
        return battleId;
    }

    // ---------- 加入对战 ----------

    /// @notice 玩家2加入对战（必须持有 Agent NFT）
    /// @param battleId 对战 ID
    /// @param nftId    玩家2使用的 Agent NFT ID
    function joinBattle(uint256 battleId, uint256 nftId) external payable {
        Battle storage b = battles[battleId];
        require(b.state == BattleState.Waiting, "Arena: battle not waiting");
        require(msg.sender != b.player1, "Arena: cannot join own battle");
        require(msg.value == b.stake, "Arena: stake mismatch");
        require(agentNFT.ownerOf(nftId) == msg.sender, "Arena: not your NFT");
        require(nftId != b.nftId1, "Arena: NFT already in battle");

        b.player2 = msg.sender;
        b.nftId2 = nftId;
        b.state = BattleState.InProgress;
        b.currentRound = 1;

        rounds[battleId][1] = Round({
            p1Move: MoveType.None,
            p2Move: MoveType.None,
            result: RoundResult.Pending,
            p1Submitted: false,
            p2Submitted: false
        });

        emit BattleStarted(
            battleId,
            b.player1, b.player2,
            b.nftId1, b.nftId2,
            b.maxRounds,
            block.timestamp
        );
    }

    // ---------- 提交动作 ----------

    /// @notice 提交本轮动作
    /// @param battleId 对战 ID
    /// @param move     动作 (1=Rock, 2=Paper, 3=Scissors)
    function submitMove(uint256 battleId, MoveType move) external {
        Battle storage b = battles[battleId];
        require(b.state == BattleState.InProgress, "Arena: battle not in progress");
        require(move != MoveType.None, "Arena: invalid move");
        require(
            msg.sender == b.player1 || msg.sender == b.player2,
            "Arena: not a battle player"
        );

        Round storage r = rounds[battleId][b.currentRound];

        if (msg.sender == b.player1) {
            require(!r.p1Submitted, "Arena: P1 already moved");
            r.p1Move = move;
            r.p1Submitted = true;
        } else {
            require(!r.p2Submitted, "Arena: P2 already moved");
            r.p2Move = move;
            r.p2Submitted = true;
        }

        emit MoveExecuted(battleId, b.currentRound, msg.sender, move, block.timestamp);

        if (r.p1Submitted && r.p2Submitted) {
            _resolveRound(battleId);
        }
    }

    // ---------- 取消对战 ----------

    /// @notice 创建者取消未开始的对战
    function cancelBattle(uint256 battleId) external {
        Battle storage b = battles[battleId];
        require(b.state == BattleState.Waiting, "Arena: can only cancel waiting");
        require(msg.sender == b.player1, "Arena: only creator can cancel");

        b.state = BattleState.Finished;

        if (b.stake > 0) {
            (bool sent, ) = b.player1.call{value: b.stake}("");
            require(sent, "Arena: refund failed");
        }

        emit BattleCancelled(battleId, msg.sender);
    }

    // ============================================================
    //  内部逻辑
    // ============================================================

    function _resolveRound(uint256 battleId) internal {
        Battle storage b = battles[battleId];
        Round storage r = rounds[battleId][b.currentRound];

        r.result = _compareMoves(r.p1Move, r.p2Move);

        if (r.result == RoundResult.Player1Win) {
            b.p1Score++;
        } else if (r.result == RoundResult.Player2Win) {
            b.p2Score++;
        }

        emit RoundResolved(
            battleId, b.currentRound,
            r.p1Move, r.p2Move, r.result,
            b.p1Score, b.p2Score
        );

        if (b.p1Score >= b.winsNeeded || b.p2Score >= b.winsNeeded) {
            _endBattle(battleId);
        } else if (b.currentRound >= b.maxRounds) {
            _endBattle(battleId);
        } else {
            b.currentRound++;
            rounds[battleId][b.currentRound] = Round({
                p1Move: MoveType.None,
                p2Move: MoveType.None,
                result: RoundResult.Pending,
                p1Submitted: false,
                p2Submitted: false
            });
        }
    }

    function _compareMoves(MoveType p1, MoveType p2)
        internal pure returns (RoundResult)
    {
        if (p1 == p2) return RoundResult.Draw;
        bool p1Wins =
            (p1 == MoveType.Rock     && p2 == MoveType.Scissors) ||
            (p1 == MoveType.Paper    && p2 == MoveType.Rock)     ||
            (p1 == MoveType.Scissors && p2 == MoveType.Paper);
        return p1Wins ? RoundResult.Player1Win : RoundResult.Player2Win;
    }

    // ============================================================
    //  对战结束 — NFT 经验 + 排行榜 + 奖金
    // ============================================================

    function _endBattle(uint256 battleId) internal {
        Battle storage b = battles[battleId];
        b.state = BattleState.Finished;
        b.endedAt = block.timestamp;

        if (b.p1Score > b.p2Score) {
            b.winner = b.player1;
            b.loser  = b.player2;
        } else if (b.p2Score > b.p1Score) {
            b.winner = b.player2;
            b.loser  = b.player1;
        } else {
            b.isDraw = true;
        }

        _updatePlayerStats(battleId);
        _updateNFTs(battleId);
        _updateLeaderboard(battleId);
        _distributeStake(battleId);

        emit BattleEnded(
            battleId,
            b.winner, b.loser, b.isDraw,
            b.p1Score, b.p2Score,
            b.isDraw ? 0 : (b.winner == b.player1 ? b.nftId1 : b.nftId2),
            b.isDraw ? 0 : (b.loser  == b.player1 ? b.nftId1 : b.nftId2),
            block.timestamp
        );
    }

    /// @dev 更新 NFT 经验值和对战记录
    function _updateNFTs(uint256 battleId) internal {
        Battle storage b = battles[battleId];

        if (b.isDraw) {
            // 平局：双方各 +20 XP
            try agentNFT.recordBattle(b.nftId1, false) {} catch {}
            try agentNFT.recordBattle(b.nftId2, false) {} catch {}
            try agentNFT.addExperience(b.nftId1, XP_DRAW) {} catch {}
            try agentNFT.addExperience(b.nftId2, XP_DRAW) {} catch {}
        } else {
            // 胜者 +50 XP，败者 +10 XP
            uint256 winnerNft = (b.winner == b.player1) ? b.nftId1 : b.nftId2;
            uint256 loserNft  = (b.loser  == b.player1) ? b.nftId1 : b.nftId2;

            try agentNFT.recordBattle(winnerNft, true) {} catch {}
            try agentNFT.recordBattle(loserNft, false) {} catch {}
            try agentNFT.addExperience(winnerNft, XP_WIN) {} catch {}
            try agentNFT.addExperience(loserNft, XP_LOSS) {} catch {}
        }
    }

    function _updatePlayerStats(uint256 battleId) internal {
        Battle storage b = battles[battleId];

        playerStats[b.player1].totalBattles++;
        playerStats[b.player2].totalBattles++;

        if (b.isDraw) {
            playerStats[b.player1].draws++;
            playerStats[b.player2].draws++;
        } else {
            playerStats[b.winner].wins++;
            playerStats[b.winner].currentStreak++;
            if (playerStats[b.winner].currentStreak > playerStats[b.winner].bestStreak) {
                playerStats[b.winner].bestStreak = playerStats[b.winner].currentStreak;
            }
            playerStats[b.loser].losses++;
            playerStats[b.loser].currentStreak = 0;
        }
    }

    function _updateLeaderboard(uint256 battleId) internal {
        Battle storage b = battles[battleId];

        if (b.isDraw) {
            try leaderboard.completeTask(b.player1, taskBattleDraw) {} catch {}
            try leaderboard.completeTask(b.player2, taskBattleDraw) {} catch {}
        } else {
            try leaderboard.completeTask(b.winner, taskBattleWin) {} catch {}
            if (playerStats[b.winner].currentStreak >= 3) {
                try leaderboard.completeTask(b.winner, taskWinStreak3) {} catch {}
            }
        }
    }

    function _distributeStake(uint256 battleId) internal {
        Battle storage b = battles[battleId];

        if (b.stake == 0) return;

        if (b.isDraw) {
            (bool s1, ) = b.player1.call{value: b.stake}("");
            (bool s2, ) = b.player2.call{value: b.stake}("");
            require(s1 && s2, "Arena: draw refund failed");
        } else {
            uint256 total = b.stake * 2;
            (bool sent, ) = b.winner.call{value: total}("");
            require(sent, "Arena: winner transfer failed");
        }
    }

    // ============================================================
    //  查询函数
    // ============================================================

    /// @notice 获取对战完整信息
    function getBattle(uint256 battleId)
        external
        view
        returns (
            address player1,
            address player2,
            uint256 nftId1,
            uint256 nftId2,
            BattleState state,
            uint256 stake,
            uint256 maxRounds,
            uint256 currentRound,
            uint256 p1Score,
            uint256 p2Score,
            address winner,
            bool isDraw
        )
    {
        Battle storage b = battles[battleId];
        return (
            b.player1, b.player2, b.nftId1, b.nftId2,
            b.state, b.stake, b.maxRounds, b.currentRound,
            b.p1Score, b.p2Score, b.winner, b.isDraw
        );
    }

    /// @notice 获取某轮信息
    function getRound(uint256 battleId, uint256 roundIndex)
        external
        view
        returns (
            MoveType p1Move,
            MoveType p2Move,
            RoundResult result,
            bool p1Submitted,
            bool p2Submitted
        )
    {
        Round storage r = rounds[battleId][roundIndex];
        return (r.p1Move, r.p2Move, r.result, r.p1Submitted, r.p2Submitted);
    }

    /// @notice 获取玩家统计
    function getPlayerStats(address player)
        external
        view
        returns (
            uint256 wins,
            uint256 losses,
            uint256 draws,
            uint256 currentStreak,
            uint256 bestStreak,
            uint256 totalBattles
        )
    {
        PlayerStats storage s = playerStats[player];
        return (s.wins, s.losses, s.draws, s.currentStreak, s.bestStreak, s.totalBattles);
    }

    /// @notice 获取对战总数
    function getTotalBattles() external view returns (uint256) {
        return battles.length;
    }

    /// @notice 检查对战是否在进行中
    function isBattleActive(uint256 battleId) external view returns (bool) {
        return battles[battleId].state == BattleState.InProgress;
    }

    /// @notice 获取当前轮次提交状态
    function getCurrentRoundStatus(uint256 battleId)
        external
        view
        returns (bool p1Ready, bool p2Ready)
    {
        Battle storage b = battles[battleId];
        if (b.state != BattleState.InProgress) return (false, false);
        Round storage r = rounds[battleId][b.currentRound];
        return (r.p1Submitted, r.p2Submitted);
    }

    /// @notice 获取对战双方 NFT 等级
    function getBattleNFTLevels(uint256 battleId)
        external
        view
        returns (uint256 level1, uint256 level2)
    {
        Battle storage b = battles[battleId];
        if (b.nftId1 > 0) level1 = agentNFT.getLevel(b.nftId1);
        if (b.nftId2 > 0) level2 = agentNFT.getLevel(b.nftId2);
    }

    receive() external payable {}
}
