// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title AgentNFT
 * @dev  Monad Buidler Camp — Week 2 Day 5
 *       AI Agent 竞技场 — Agent NFT (ERC-721)
 *
 * 设计理念：
 *   1. 每个 Agent 是一个独一无二的 NFT，拥有 5 项属性
 *   2. 属性范围 1-100，Mint 时由 blockhash + sender 随机生成
 *   3. 对战胜利 → 获得经验值 → 升级 → 属性提升
 *   4. 授权合约（BattleEngine）可为 NFT 添加经验
 *   5. 纯手写 ERC-721，无外部依赖，可直接在 Remix 编译
 *
 * 属性体系：
 *   ┌──────────────────────────────────────────┐
 *   │            Agent NFT 属性体系             │
 *   ├──────────┬───────────────────────────────┤
 *   │ strength │ 攻击力 — 影响攻击伤害          │
 *   │ speed    │ 速度   — 影响出手顺序 / 闪避   │
 *   │ strategy │ 策略   — 影响暴击率            │
 *   │ defense  │ 防御   — 减少受到的伤害        │
 *   │ luck     │ 运气   — 随机增益             │
 *   └──────────┴───────────────────────────────┘
 *
 * 升级机制：
 *   - Level 1 → 2: 需要 100 XP
 *   - Level N → N+1: 需要 N * 100 XP
 *   - 每次升级随机提升 1 项属性 +1 ~ +3
 *   - 属性上限 100
 */

contract AgentNFT {

    // ============================================================
    //  ERC-721 数据结构
    // ============================================================

    /// @dev tokenId → 持有者地址
    mapping(uint256 => address) private _owners;

    /// @dev 地址 → 持有 NFT 数量
    mapping(address => uint256) private _balances;

    /// @dev tokenId → 授权地址
    mapping(uint256 => address) private _tokenApprovals;

    /// @dev owner → operator → 是否批量授权
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    /// @dev tokenId → tokenURI（元数据链接）
    mapping(uint256 => string) private _tokenURIs;

    // ============================================================
    //  Agent 属性结构
    // ============================================================

    struct AgentStats {
        uint256 strength;     // 攻击力 1-100
        uint256 speed;        // 速度 1-100
        uint256 strategy;     // 策略 1-100
        uint256 defense;      // 防御 1-100
        uint256 luck;         // 运气 1-100
        uint256 level;        // 等级（从 1 开始）
        uint256 experience;   // 当前经验值
        uint256 expToNext;    // 升级所需经验
        uint256 totalBattles; // 总对战次数
        uint256 wins;         // 胜利次数
        uint256 mintedAt;     // 创建时间
    }

    /// @dev tokenId → Agent 属性
    mapping(uint256 => AgentStats) public agents;

    /// @dev 所有已铸造的 tokenId 列表
    uint256[] private _allTokens;

    /// @dev owner → tokenId 列表
    mapping(address => uint256[]) private _ownedTokens;

    /// @dev tokenId → 在 _ownedTokens 中的索引
    mapping(uint256 => uint256) private _ownedTokensIndex;

    // ============================================================
    //  权限与配置
    // ============================================================

    address public owner;
    mapping(address => bool) public authorizedContracts; // 授权合约（如 BattleEngine）

    /// @dev 下一个 tokenId（从 1 开始，0 保留为空）
    uint256 public nextTokenId;

    /// @dev Mint 价格（可设为 0）
    uint256 public mintPrice;

    /// @dev 最大属性值
    uint256 public constant MAX_STAT = 100;

    /// @dev 属性数量
    uint256 public constant STAT_COUNT = 5;

    // ============================================================
    //  事件
    // ============================================================

    // --- ERC-721 标准事件 ---

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    // --- Agent 专用事件 ---

    event AgentMinted(
        uint256 indexed tokenId,
        address indexed minter,
        uint256 strength,
        uint256 speed,
        uint256 strategy,
        uint256 defense,
        uint256 luck,
        uint256 timestamp
    );

    event ExperienceGained(
        uint256 indexed tokenId,
        uint256 expGained,
        uint256 totalExp,
        uint256 timestamp
    );

    event LevelUp(
        uint256 indexed tokenId,
        uint256 newLevel,
        string statIncreased,
        uint256 increaseAmount,
        uint256 timestamp
    );

    event AuthorizedContractAdded(address indexed contractAddr);
    event AuthorizedContractRemoved(address indexed contractAddr);
    event MintPriceUpdated(uint256 oldPrice, uint256 newPrice);

    // ============================================================
    //  修饰符
    // ============================================================

    modifier onlyOwner() {
        require(msg.sender == owner, "AgentNFT: not owner");
        _;
    }

    modifier onlyAuthorized() {
        require(
            authorizedContracts[msg.sender] || msg.sender == owner,
            "AgentNFT: not authorized"
        );
        _;
    }

    modifier onlyTokenOwner(uint256 tokenId) {
        require(_owners[tokenId] == msg.sender, "AgentNFT: not token owner");
        _;
    }

    modifier exists(uint256 tokenId) {
        require(_owners[tokenId] != address(0), "AgentNFT: token does not exist");
        _;
    }

    // ============================================================
    //  构造函数
    // ============================================================

    /// @param mintPrice_ Mint 价格（0 = 免费）
    constructor(uint256 mintPrice_) {
        owner = msg.sender;
        mintPrice = mintPrice_;
        nextTokenId = 1; // tokenId 从 1 开始
    }

    // ============================================================
    //  ERC-721 标准函数 — 查询
    // ============================================================

    /// @notice 查询某地址持有的 NFT 数量
    function balanceOf(address account) external view returns (uint256) {
        require(account != address(0), "AgentNFT: zero address");
        return _balances[account];
    }

    /// @notice 查询 tokenId 的持有者
    function ownerOf(uint256 tokenId) public view returns (address) {
        address tokenOwner = _owners[tokenId];
        require(tokenOwner != address(0), "AgentNFT: token does not exist");
        return tokenOwner;
    }

    /// @notice 查询 tokenId 的授权地址
    function getApproved(uint256 tokenId) external view exists(tokenId) returns (address) {
        return _tokenApprovals[tokenId];
    }

    /// @notice 查询是否批量授权
    function isApprovedForAll(address account, address operator) public view returns (bool) {
        return _operatorApprovals[account][operator];
    }

    /// @notice 查询 tokenURI
    function tokenURI(uint256 tokenId) external view exists(tokenId) returns (string memory) {
        return _tokenURIs[tokenId];
    }

    /// @notice 查询已铸造总数
    function totalSupply() external view returns (uint256) {
        return _allTokens.length;
    }

    // ============================================================
    //  ERC-721 标准函数 — 转移
    // ============================================================

    /// @notice 转移 NFT
    function transferFrom(address from, address to, uint256 tokenId) public {
        require(_isAuthorized(msg.sender, tokenId), "AgentNFT: not authorized to transfer");
        require(_owners[tokenId] == from, "AgentNFT: wrong from address");
        require(to != address(0), "AgentNFT: transfer to zero address");

        _transfer(from, to, tokenId);
    }

    /// @notice 安全转移 NFT（检查接收方是否实现了 onERC721Received）
    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        _safeTransfer(from, to, tokenId, "");
    }

    /// @notice 安全转移 NFT（带 data）
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public {
        _safeTransfer(from, to, tokenId, data);
    }

    function _safeTransfer(address from, address to, uint256 tokenId, bytes memory data) internal {
        transferFrom(from, to, tokenId);
        require(
            _checkOnERC721Received(from, to, tokenId, data),
            "AgentNFT: transfer to non ERC721Receiver"
        );
    }

    // ============================================================
    //  ERC-721 标准函数 — 授权
    // ============================================================

    /// @notice 授权某地址操作指定 NFT
    function approve(address to, uint256 tokenId) external onlyTokenOwner(tokenId) {
        _tokenApprovals[tokenId] = to;
        emit Approval(msg.sender, to, tokenId);
    }

    /// @notice 批量授权某地址操作所有 NFT
    function setApprovalForAll(address operator, bool approved) external {
        require(operator != msg.sender, "AgentNFT: approve to self");
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    // ============================================================
    //  内部函数 — 转移与授权
    // ============================================================

    function _isAuthorized(address spender, uint256 tokenId) internal view returns (bool) {
        address tokenOwner = _owners[tokenId];
        return spender == tokenOwner
            || _tokenApprovals[tokenId] == spender
            || isApprovedForAll(tokenOwner, spender);
    }

    function _transfer(address from, address to, uint256 tokenId) internal {
        // 清除单个授权
        _tokenApprovals[tokenId] = address(0);
        emit Approval(from, address(0), tokenId);

        // 更新余额
        _balances[from]--;
        _balances[to]++;

        // 更新持有者
        _owners[tokenId] = to;

        // 更新 _ownedTokens 索引
        _removeTokenFromOwner(from, tokenId);
        _addTokenToOwner(to, tokenId);

        emit Transfer(from, to, tokenId);
    }

    function _checkOnERC721Received(address from, address to, uint256 tokenId, bytes memory data)
        internal returns (bool)
    {
        // 如果接收方是合约，检查是否实现了 onERC721Received
        if (to.code.length == 0) return true; // EOA 地址，无需检查

        try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, data) returns (bytes4 retval) {
            return retval == IERC721Receiver.onERC721Received.selector;
        } catch {
            return false;
        }
    }

    // ============================================================
    //  内部函数 — _ownedTokens 管理
    // ============================================================

    function _addTokenToOwner(address to, uint256 tokenId) internal {
        _ownedTokensIndex[tokenId] = _ownedTokens[to].length;
        _ownedTokens[to].push(tokenId);
    }

    function _removeTokenFromOwner(address from, uint256 tokenId) internal {
        uint256 lastIndex = _ownedTokens[from].length - 1;
        uint256 tokenIndex = _ownedTokensIndex[tokenId];

        if (tokenIndex != lastIndex) {
            uint256 lastTokenId = _ownedTokens[from][lastIndex];
            _ownedTokens[from][tokenIndex] = lastTokenId;
            _ownedTokensIndex[lastTokenId] = tokenIndex;
        }

        _ownedTokens[from].pop();
        delete _ownedTokensIndex[tokenId];
    }

    function _addTokenToAllTokens(uint256 tokenId) internal {
        _allTokens.push(tokenId);
    }

    // ============================================================
    //  枚举扩展 — ERC-721 Enumerable
    // ============================================================

    /// @notice 按全局索引获取 tokenId
    function tokenByIndex(uint256 index) external view returns (uint256) {
        require(index < _allTokens.length, "AgentNFT: index out of bounds");
        return _allTokens[index];
    }

    /// @notice 按持有者和索引获取 tokenId
    function tokenOfOwnerByIndex(address account, uint256 index) external view returns (uint256) {
        require(index < _ownedTokens[account].length, "AgentNFT: index out of bounds");
        return _ownedTokens[account][index];
    }

    /// @notice 获取某地址持有的所有 tokenId
    function tokensOfOwner(address account) external view returns (uint256[] memory) {
        return _ownedTokens[account];
    }

    // ============================================================
    //  Mint — 铸造 Agent
    // ============================================================

    /// @notice 铸造一个新 Agent NFT
    /// @dev    属性由 blockhash + msg.sender + nextTokenId 伪随机生成
    ///         属性范围 40-80（保证初始不会太强也不会太弱）
    /// @param uri_ 元数据 URI（可空字符串）
    /// @return tokenId 新铸造的 NFT ID
    function mintAgent(string memory uri_) external payable returns (uint256) {
        require(msg.value >= mintPrice, "AgentNFT: insufficient mint payment");

        uint256 tokenId = nextTokenId++;
        address minter = msg.sender;

        // ---- 伪随机数生成 ----
        // 注意：blockhash 在 Remix 测试环境中可能返回 0
        // 生产环境应使用 Chainlink VRF
        uint256 seed = uint256(
            keccak256(abi.encodePacked(
                blockhash(block.number - 1),
                minter,
                tokenId,
                block.timestamp,
                gasleft()
            ))
        );

        // ---- 生成 5 项属性（范围 40-80）----
        uint256 _strength = _randomStat(seed, 0);
        uint256 _speed    = _randomStat(seed, 1);
        uint256 _strategy = _randomStat(seed, 2);
        uint256 _defense  = _randomStat(seed, 3);
        uint256 _luck     = _randomStat(seed, 4);

        // ---- 写入属性 ----
        agents[tokenId] = AgentStats({
            strength:     _strength,
            speed:        _speed,
            strategy:     _strategy,
            defense:      _defense,
            luck:         _luck,
            level:        1,
            experience:   0,
            expToNext:    100, // Level 1 → 2 需要 100 XP
            totalBattles: 0,
            wins:         0,
            mintedAt:     block.timestamp
        });

        // ---- 更新 ERC-721 状态 ----
        _owners[tokenId] = minter;
        _balances[minter]++;
        _addTokenToOwner(minter, tokenId);
        _addTokenToAllTokens(tokenId);

        // ---- 设置 tokenURI ----
        _tokenURIs[tokenId] = uri_;

        emit Transfer(address(0), minter, tokenId);
        emit AgentMinted(tokenId, minter, _strength, _speed, _strategy, _defense, _luck, block.timestamp);

        return tokenId;
    }

    /// @dev 从 seed 生成单个属性（范围 40-80）
    function _randomStat(uint256 seed, uint256 offset) internal pure returns (uint256) {
        // 取 seed 的某一段，映射到 40-80
        uint256 rand = uint256(keccak256(abi.encodePacked(seed, offset)));
        return 40 + (rand % 41); // 40 + (0~40) = 40~80
    }

    // ============================================================
    //  经验值与升级 — 供 BattleEngine 调用
    // ============================================================

    /// @notice 为 Agent 添加经验值（仅授权合约可调用）
    /// @param tokenId   Agent ID
    /// @param exp       经验值
    function addExperience(uint256 tokenId, uint256 exp) external onlyAuthorized exists(tokenId) {
        AgentStats storage agent = agents[tokenId];
        agent.experience += exp;

        emit ExperienceGained(tokenId, exp, agent.experience, block.timestamp);

        // 检查是否可以升级（可能一次加很多经验，连升多级）
        while (agent.experience >= agent.expToNext) {
            agent.experience -= agent.expToNext;
            _levelUp(tokenId);
        }
    }

    /// @notice 记录一场对战结果（仅授权合约可调用）
    /// @param tokenId Agent ID
    /// @param won     是否胜利
    function recordBattle(uint256 tokenId, bool won) external onlyAuthorized exists(tokenId) {
        AgentStats storage agent = agents[tokenId];
        agent.totalBattles++;
        if (won) {
            agent.wins++;
        }
    }

    /// @dev 内部升级逻辑 — 随机提升 1 项属性
    function _levelUp(uint256 tokenId) internal {
        AgentStats storage agent = agents[tokenId];
        agent.level++;

        // 更新升级所需经验（每级 +100）
        agent.expToNext = agent.level * 100;

        // 随机选择提升的属性
        uint256 seed = uint256(keccak256(abi.encodePacked(
            blockhash(block.number - 1),
            tokenId,
            agent.level,
            block.timestamp
        )));

        uint256 statIndex = seed % STAT_COUNT; // 0-4
        uint256 increase = 1 + (seed % 3);    // +1 ~ +3

        string memory statName;

        if (statIndex == 0) {
            agent.strength = _min(agent.strength + increase, MAX_STAT);
            statName = "strength";
        } else if (statIndex == 1) {
            agent.speed = _min(agent.speed + increase, MAX_STAT);
            statName = "speed";
        } else if (statIndex == 2) {
            agent.strategy = _min(agent.strategy + increase, MAX_STAT);
            statName = "strategy";
        } else if (statIndex == 3) {
            agent.defense = _min(agent.defense + increase, MAX_STAT);
            statName = "defense";
        } else {
            agent.luck = _min(agent.luck + increase, MAX_STAT);
            statName = "luck";
        }

        emit LevelUp(tokenId, agent.level, statName, increase, block.timestamp);
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    // ============================================================
    //  管理函数
    // ============================================================

    /// @notice 添加授权合约（如 BattleEngine）
    function addAuthorizedContract(address contractAddr) external onlyOwner {
        authorizedContracts[contractAddr] = true;
        emit AuthorizedContractAdded(contractAddr);
    }

    /// @notice 移除授权合约
    function removeAuthorizedContract(address contractAddr) external onlyOwner {
        authorizedContracts[contractAddr] = false;
        emit AuthorizedContractRemoved(contractAddr);
    }

    /// @notice 更新 Mint 价格
    function setMintPrice(uint256 newPrice) external onlyOwner {
        uint256 old = mintPrice;
        mintPrice = newPrice;
        emit MintPriceUpdated(old, newPrice);
    }

    /// @notice 提取合约中的 ETH
    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "AgentNFT: no balance");
        (bool sent, ) = owner.call{value: balance}("");
        require(sent, "AgentNFT: withdraw failed");
    }

    // ============================================================
    //  查询函数 — Agent 属性
    // ============================================================

    /// @notice 获取 Agent 完整属性
    /// @return strength   攻击力
    /// @return speed      速度
    /// @return strategy   策略
    /// @return defense    防御
    /// @return luck       运气
    /// @return level      等级
    /// @return experience 当前经验
    /// @return expToNext  升级所需
    /// @return totalBattles 总对战
    /// @return wins       胜利次数
    /// @return mintedAt   创建时间
    function getAgent(uint256 tokenId)
        external
        view
        exists(tokenId)
        returns (
            uint256 strength,
            uint256 speed,
            uint256 strategy,
            uint256 defense,
            uint256 luck,
            uint256 level,
            uint256 experience,
            uint256 expToNext,
            uint256 totalBattles,
            uint256 wins,
            uint256 mintedAt
        )
    {
        AgentStats storage a = agents[tokenId];
        return (
            a.strength, a.speed, a.strategy, a.defense, a.luck,
            a.level, a.experience, a.expToNext,
            a.totalBattles, a.wins, a.mintedAt
        );
    }

    /// @notice 获取 Agent 的战力总值（5 项属性之和）
    function getTotalPower(uint256 tokenId) external view exists(tokenId) returns (uint256) {
        AgentStats storage a = agents[tokenId];
        return a.strength + a.speed + a.strategy + a.defense + a.luck;
    }

    /// @notice 获取 Agent 胜率（万分比，例如 7500 = 75%）
    function getWinRate(uint256 tokenId) external view exists(tokenId) returns (uint256) {
        AgentStats storage a = agents[tokenId];
        if (a.totalBattles == 0) return 0;
        return (a.wins * 10000) / a.totalBattles;
    }

    /// @notice 获取 Agent 等级
    function getLevel(uint256 tokenId) external view exists(tokenId) returns (uint256) {
        return agents[tokenId].level;
    }

    // ============================================================
    //  接收 ETH
    // ============================================================

    receive() external payable {}
}

// ============================================================
//  接口 — ERC-721 Receiver
// ============================================================

interface IERC721Receiver {
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}
