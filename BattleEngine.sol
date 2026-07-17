// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title BattleEngine
 * @dev  Monad Buidler Camp — Week 2
 *       AI Agent 竞技场核心对战引擎
 *
 * 设计理念：
 *   1. 状态机驱动 — 每场对战经历 Waiting → InProgress → Finished 三个阶段
 *   2. 可验证公平 — 所有动作上链，任何人可审计对战过程和结果
 *   3. 多轮制 — Best of N（奇数轮），先达到胜需轮数者获胜
 *   4. 排行榜集成 — 对战结果通过 ScoreLeaderboard.completeTask 更新分数
 *
 * 与 ScoreLeaderboard 的集成方式：
 *   - 部署 ScoreLeaderboard 后，部署 BattleEngine(leaderboard 地址)
 *   - 调用 initialize() 在排行榜上注册里程碑任务
 *   - BattleEngine 自动成为排行榜的验证者
 *   - 对战结束后，胜者获得 "Battle Win" 分数（5 分）
 *   - 3 连胜解锁 "Win Streak x3" 额外奖励（10 分）
 *
 * 注意：
 *   当前 submitMove 为直接提交模式（演示用）。
 *   生产环境应使用 commit-reveal 防止前跑：
 *     1. commitMove(battleId, hash(move, salt))  — 先提交哈希
 *     2. revealMove(battleId, move, salt)        — 再揭示明文
 *   本合约预留了扩展注释，Week 3 可实现。
 */

// ============================================================
//  接口 — 只声明 BattleEngine 需要调用的函数
// ============================================================

interface IScoreLeaderboard {
    function completeTask(address user, uint256 taskId) external;
    function addVerifier(address verifier) external;
    function registerTask(string memory name, uint256 points) external returns (uint256);
}

// ============================================================
//  主合约
// ============================================================

contract BattleEngine {

    // ============================================================
    //  枚举
    // ============================================================

    /// @dev 对战状态：等待加入 → 对战中 → 已结束
    enum BattleState { Waiting, InProgress, Finished }

    /// @dev 动作类型 — Rock-Paper-Scissors（可扩展为 AI Agent 动作）
    ///      0=None(未提交), 1=Rock, 2=Paper, 3=Scissors
    enum MoveType { None, Rock, Paper, Scissors }

    /// @dev 单轮结果 — 0=待定, 1=平局, 2=P1胜, 3=P2胜
    enum RoundResult { Pending, Draw, Player1Win, Player2Win }

    // ============================================================
    //  结构体
    // ============================================================

    /// @dev 一场对战
    struct Battle {
        address player1;        // 创建者
        address player2;        // 挑战者
        uint256 stake;           // 入场费（MON），可为 0
        BattleState state;       // 当前状态
        uint256 maxRounds;       // 最大轮数（奇数：1/3/5/7/9）
        uint256 winsNeeded;      // 获胜所需轮数 (maxRounds/2 + 1)
        uint256 currentRound;    // 当前轮次（1-indexed）
        uint256 p1Score;         // P1 胜轮数
        uint256 p2Score;         // P2 胜轮数
        address winner;          // 胜者（平局为 address(0)）
        address loser;           // 败者（平局为 address(0)）
        bool isDraw;             // 是否平局
        uint256 createdAt;       // 创建时间
        uint256 endedAt;         // 结束时间
    }

    /// @dev 单轮记录
    struct Round {
        MoveType p1Move;         // P1 动作
        MoveType p2Move;         // P2 动作
        RoundResult result;      // 本轮结果
        bool p1Submitted;        // P1 是否已提交
        bool p2Submitted;        // P2 是否已提交
    }

    /// @dev 玩家统计
    struct PlayerStats {
        uint256 wins;
        uint256 losses;
        uint256 draws;
        uint256 currentStreak;   // 当前连胜
        uint256 bestStreak;      // 历史最佳连胜
        uint256 totalBattles;
    }

    // ============================================================
    //  存储
    // ============================================================

    IScoreLeaderboard public leaderboard;   // 排行榜合约引用
    address public owner;                    // 合约部署者

    /// @dev 所有对战（battleId = 数组索引）
    Battle[] public battles;

    /// @dev battleId => roundIndex => Round（roundIndex 从 1 开始）
    mapping(uint256 => mapping(uint256 => Round)) public rounds;

    /// @dev 玩家地址 => 统计
    mapping(address => PlayerStats) public playerStats;

    /// @dev 是否已初始化（防止重复调用 initialize）
    bool public initialized;

    // --- 里程碑任务 ID（由 initialize() 在 ScoreLeaderboard 上注册）---

    /// @dev "Battle Win" 任务 ID — 首次对战胜利得 5 分
    uint256 public taskBattleWin;

    /// @dev "Battle Draw" 任务 ID — 首次平局得 2 分
    uint256 public taskBattleDraw;

    /// @dev "Win Streak x3" 任务 ID — 首次 3 连胜得 10 分
    uint256 public taskWinStreak3;

    // ============================================================
    //  事件
    // ============================================================

    event BattleCreated(
        uint256 indexed battleId,
        address indexed player1,
        uint256 stake,
        uint256 maxRounds
    );

    event BattleStarted(
        uint256 indexed battleId,
        address indexed player1,
        address indexed player2,
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
        uint256 timestamp
    );

    event BattleCancelled(uint256 indexed battleId, address indexed creator);

    event Initialized(address leaderboard, uint256 taskWin, uint256 taskDraw, uint256 taskStreak);

    // ============================================================
    //  修饰符
    // ============================================================

    modifier onlyOwner() {
        require(msg.sender == owner, "BattleEngine: caller is not owner");
        _;
    }

    modifier notInitialized() {
        require(!initialized, "BattleEngine: already initialized");
        _;
    }

    // ============================================================
    //  构造函数
    // ============================================================

    /// @param leaderboard_ ScoreLeaderboard 合约地址
    constructor(address leaderboard_) {
        owner = msg.sender;
        leaderboard = IScoreLeaderboard(leaderboard_);
    }

    /// @notice 初始化 — 在排行榜上注册里程碑任务，并把自己设为验证者
    /// @dev    部署后调用一次。需要调用者是 ScoreLeaderboard 的 owner。
    ///         如果 BattleEngine 部署者不是 ScoreLeaderboard 的 owner，
    ///         需要先用 ScoreLeaderboard.addVerifier(battleEngine 地址) 手动授权。
    function initialize() external onlyOwner notInitialized {
        // 注册里程碑任务（返回的 taskId 存储供后续使用）
        taskBattleWin   = leaderboard.registerTask("Battle Win",     5);
        taskBattleDraw  = leaderboard.registerTask("Battle Draw",    2);
        taskWinStreak3  = leaderboard.registerTask("Win Streak x3", 10);

        // 将 BattleEngine 设为排行榜验证者
        // 注意：调用 addVerifier 的必须是 ScoreLeaderboard 的 owner
        // 如果 BattleEngine 部署者 == ScoreLeaderboard 部署者，此处直接成功
        try leaderboard.addVerifier(address(this)) {} catch {}

        initialized = true;

        emit Initialized(
            address(leaderboard),
            taskBattleWin,
            taskBattleDraw,
            taskWinStreak3
        );
    }

    // ============================================================
    //  核心逻辑 — 对战生命周期
    // ============================================================

    // ---------- 创建对战 ----------

    /// @notice 创建一场新对战（玩家1发起）
    /// @param maxRounds 最大轮数（必须是奇数：1/3/5/7/9）
    /// @return battleId 对战 ID
    function createBattle(uint256 maxRounds) external payable returns (uint256) {
        require(maxRounds % 2 == 1, "BattleEngine: maxRounds must be odd");
        require(maxRounds >= 1 && maxRounds <= 9, "BattleEngine: maxRounds 1-9");

        uint256 battleId = battles.length;

        battles.push(Battle({
            player1:     msg.sender,
            player2:     address(0),
            stake:       msg.value,
            state:       BattleState.Waiting,
            maxRounds:   maxRounds,
            winsNeeded:  (maxRounds / 2) + 1,
            currentRound: 0,
            p1Score:     0,
            p2Score:     0,
            winner:      address(0),
            loser:       address(0),
            isDraw:      false,
            createdAt:   block.timestamp,
            endedAt:     0
        }));

        emit BattleCreated(battleId, msg.sender, msg.value, maxRounds);
        return battleId;
    }

    // ---------- 加入对战 ----------

    /// @notice 玩家2加入对战
    /// @param battleId 对战 ID
    function joinBattle(uint256 battleId) external payable {
        Battle storage b = battles[battleId];
        require(b.state == BattleState.Waiting, "BattleEngine: battle not waiting");
        require(msg.sender != b.player1, "BattleEngine: cannot join own battle");
        require(msg.value == b.stake, "BattleEngine: stake mismatch");

        b.player2 = msg.sender;
        b.state = BattleState.InProgress;
        b.currentRound = 1; // 从第 1 轮开始

        // 初始化第 1 轮
        rounds[battleId][1] = Round({
            p1Move: MoveType.None,
            p2Move: MoveType.None,
            result: RoundResult.Pending,
            p1Submitted: false,
            p2Submitted: false
        });

        emit BattleStarted(
            battleId,
            b.player1,
            b.player2,
            b.maxRounds,
            block.timestamp
        );
    }

    // ---------- 提交动作 ----------

    /// @notice 提交本轮动作
    /// @dev    当前为直接提交模式。生产环境应使用 commit-reveal：
    ///         1) commitMove(battleId, keccak256(abi.encodePacked(move, salt)))
    ///         2) revealMove(battleId, move, salt)
    ///         以防止第二个玩家看到第一个玩家的动作后选择克制动作。
    /// @param battleId 对战 ID
    /// @param move     动作类型 (1=Rock, 2=Paper, 3=Scissors)
    function submitMove(uint256 battleId, MoveType move) external {
        Battle storage b = battles[battleId];
        require(b.state == BattleState.InProgress, "BattleEngine: battle not in progress");
        require(move != MoveType.None, "BattleEngine: invalid move");
        require(
            msg.sender == b.player1 || msg.sender == b.player2,
            "BattleEngine: not a battle player"
        );

        Round storage r = rounds[battleId][b.currentRound];

        if (msg.sender == b.player1) {
            require(!r.p1Submitted, "BattleEngine: P1 already moved");
            r.p1Move = move;
            r.p1Submitted = true;
        } else {
            require(!r.p2Submitted, "BattleEngine: P2 already moved");
            r.p2Move = move;
            r.p2Submitted = true;
        }

        emit MoveExecuted(
            battleId,
            b.currentRound,
            msg.sender,
            move,
            block.timestamp
        );

        // 双方都已提交 → 解析本轮
        if (r.p1Submitted && r.p2Submitted) {
            _resolveRound(battleId);
        }
    }

    // ---------- 取消对战（仅 Waiting 状态）----------

    /// @notice 创建者取消未开始的对战，退还入场费
    /// @param battleId 对战 ID
    function cancelBattle(uint256 battleId) external {
        Battle storage b = battles[battleId];
        require(b.state == BattleState.Waiting, "BattleEngine: can only cancel waiting battle");
        require(msg.sender == b.player1, "BattleEngine: only creator can cancel");

        b.state = BattleState.Finished;

        // 退还入场费
        if (b.stake > 0) {
            (bool sent, ) = b.player1.call{value: b.stake}("");
            require(sent, "BattleEngine: refund failed");
        }

        emit BattleCancelled(battleId, msg.sender);
    }

    // ============================================================
    //  内部逻辑 — 轮次解析与胜负判定
    // ============================================================

    /// @dev 解析当前轮次：比较双方动作，更新比分，判断是否结束
    function _resolveRound(uint256 battleId) internal {
        Battle storage b = battles[battleId];
        Round storage r = rounds[battleId][b.currentRound];

        // 比较动作 — Rock-Paper-Scissors 规则
        r.result = _compareMoves(r.p1Move, r.p2Move);

        if (r.result == RoundResult.Player1Win) {
            b.p1Score++;
        } else if (r.result == RoundResult.Player2Win) {
            b.p2Score++;
        }
        // Draw: 比分不变

        emit RoundResolved(
            battleId,
            b.currentRound,
            r.p1Move,
            r.p2Move,
            r.result,
            b.p1Score,
            b.p2Score
        );

        // 判断是否结束
        if (b.p1Score >= b.winsNeeded || b.p2Score >= b.winsNeeded) {
            // 有人达到胜需轮数
            _endBattle(battleId);
        } else if (b.currentRound >= b.maxRounds) {
            // 达到最大轮数，按比分判定
            _endBattle(battleId);
        } else {
            // 进入下一轮
            b.currentRound++;

            // 初始化下一轮
            rounds[battleId][b.currentRound] = Round({
                p1Move: MoveType.None,
                p2Move: MoveType.None,
                result: RoundResult.Pending,
                p1Submitted: false,
                p2Submitted: false
            });
        }
    }

    /// @dev Rock-Paper-Scissors 胜负判定
    ///      Rock(1) beats Scissors(3), Scissors(3) beats Paper(2), Paper(2) beats Rock(1)
    function _compareMoves(MoveType p1, MoveType p2)
        internal
        pure
        returns (RoundResult)
    {
        if (p1 == p2) return RoundResult.Draw;

        bool p1Wins =
            (p1 == MoveType.Rock     && p2 == MoveType.Scissors) ||
            (p1 == MoveType.Paper    && p2 == MoveType.Rock)     ||
            (p1 == MoveType.Scissors && p2 == MoveType.Paper);

        return p1Wins ? RoundResult.Player1Win : RoundResult.Player2Win;
    }

    // ============================================================
    //  内部逻辑 — 对战结束与结算
    // ============================================================

    /// @dev 结束对战：确定胜者、更新统计、集成排行榜、分配奖金
    function _endBattle(uint256 battleId) internal {
        Battle storage b = battles[battleId];
        b.state = BattleState.Finished;
        b.endedAt = block.timestamp;

        // 确定胜负
        if (b.p1Score > b.p2Score) {
            b.winner = b.player1;
            b.loser  = b.player2;
            b.isDraw = false;
        } else if (b.p2Score > b.p1Score) {
            b.winner = b.player2;
            b.loser  = b.player1;
            b.isDraw = false;
        } else {
            b.isDraw = true;
            // winner/loser 保持 address(0)
        }

        // 更新玩家统计
        _updatePlayerStats(battleId);

        // 更新排行榜（里程碑任务）
        _updateLeaderboard(battleId);

        // 分配奖金
        _distributeStake(battleId);

        emit BattleEnded(
            battleId,
            b.winner,
            b.loser,
            b.isDraw,
            b.p1Score,
            b.p2Score,
            block.timestamp
        );
    }

    /// @dev 更新双方对战统计
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
            playerStats[b.loser].currentStreak = 0; // 连败归零
        }
    }

    /// @dev 将对战结果同步到 ScoreLeaderboard（里程碑任务）
    ///      使用 try-catch 是因为 ScoreLeaderboard 的 completeTask 有防重复检查，
    ///      同一用户不能完成同一任务两次。里程碑任务只奖励"第一次"。
    function _updateLeaderboard(uint256 battleId) internal {
        Battle storage b = battles[battleId];

        if (b.isDraw) {
            // 平局：双方各得 2 分（首次）
            try leaderboard.completeTask(b.player1, taskBattleDraw) {} catch {}
            try leaderboard.completeTask(b.player2, taskBattleDraw) {} catch {}
        } else {
            // 胜者得 5 分（首次胜利）
            try leaderboard.completeTask(b.winner, taskBattleWin) {} catch {}

            // 3 连胜额外奖励 10 分（首次达成）
            if (playerStats[b.winner].currentStreak >= 3) {
                try leaderboard.completeTask(b.winner, taskWinStreak3) {} catch {}
            }
        }
    }

    /// @dev 分配入场费
    ///      胜者通吃；平局退还双方
    function _distributeStake(uint256 battleId) internal {
        Battle storage b = battles[battleId];

        if (b.stake == 0) return; // 无入场费

        if (b.isDraw) {
            // 平局：退还双方
            (bool s1, ) = b.player1.call{value: b.stake}("");
            (bool s2, ) = b.player2.call{value: b.stake}("");
            require(s1 && s2, "BattleEngine: draw refund failed");
        } else {
            // 胜者拿走全部
            uint256 total = b.stake * 2;
            (bool sent, ) = b.winner.call{value: total}("");
            require(sent, "BattleEngine: winner transfer failed");
        }
    }

    // ============================================================
    //  查询函数 — View
    // ============================================================

    /// @notice 获取对战完整信息
    /// @return player1     玩家1地址
    /// @return player2     玩家2地址
    /// @return state       对战状态
    /// @return stake       入场费
    /// @return maxRounds   最大轮数
    /// @return currentRound 当前轮次
    /// @return p1Score     P1 胜轮数
    /// @return p2Score     P2 胜轮数
    /// @return winner      胜者地址
    /// @return isDraw      是否平局
    function getBattle(uint256 battleId)
        external
        view
        returns (
            address player1,
            address player2,
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
            b.player1, b.player2, b.state, b.stake,
            b.maxRounds, b.currentRound, b.p1Score, b.p2Score,
            b.winner, b.isDraw
        );
    }

    /// @notice 获取某轮信息
    /// @param battleId   对战 ID
    /// @param roundIndex 轮次（1-indexed）
    /// @return p1Move       P1 动作
    /// @return p2Move       P2 动作
    /// @return result       本轮结果
    /// @return p1Submitted  P1 是否已提交
    /// @return p2Submitted  P2 是否已提交
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

    /// @notice 获取玩家对战统计
    /// @return wins          胜场
    /// @return losses        败场
    /// @return draws         平局数
    /// @return currentStreak 当前连胜
    /// @return bestStreak    历史最佳连胜
    /// @return totalBattles   总对战数
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

    /// @notice 获取当前轮次双方提交状态
    /// @return p1Ready P1 是否已提交
    /// @return p2Ready P2 是否已提交
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

    // ============================================================
    //  接收 ETH（用于入场费转账）
    // ============================================================

    /// @dev 接收意外转入的 ETH
    receive() external payable {}
}
