// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Cheetah Cursor
/// @notice Cursor software–themed ERC-20 with staking, velocity tracking, and governance.
/// @dev Large contract: token, staking, roles, treasury, cursor positions, speed metrics.
contract CheetahCursor {
    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
    event Staked(address indexed user, uint256 amount, uint256 lockedUntil);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    event CursorPositionUpdated(address indexed user, uint256 x, uint256 y, uint256 timestamp);
    event VelocityRecorded(address indexed user, uint256 velocity, uint256 timestamp);
    event TreasuryDeposit(address indexed from, uint256 amount);
    event TreasuryWithdraw(address indexed to, uint256 amount, address indexed authorizedBy);
    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, string description);
    event VoteCast(uint256 indexed proposalId, address indexed voter, bool support, uint256 weight);
    event ProposalExecuted(uint256 indexed proposalId, address indexed executor);

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error Unauthorized();
    error ZeroAddress();
    error ZeroAmount();
    error InsufficientBalance();
    error InsufficientAllowance();
    error StakingLocked();
    error NoStake();
    error NoRewards();
    error ProposalNotFound();
    error ProposalExpired();
    error AlreadyVoted();
    error ProposalNotPassed();
    error MaxSupplyExceeded();
    error InvalidVelocity();
    error InvalidPosition();

    // ═══════════════════════════════════════════════════════════════════════════
    // ROLES (Cursor-style access)
    // ═══════════════════════════════════════════════════════════════════════════

    bytes32 public constant ADMIN_ROLE = keccak256("CHEETAH_CURSOR_ADMIN");
    bytes32 public constant MINTER_ROLE = keccak256("CHEETAH_CURSOR_MINTER");
    bytes32 public constant TREASURY_ROLE = keccak256("CHEETAH_CURSOR_TREASURY");
    bytes32 public constant REWARD_MANAGER_ROLE = keccak256("CHEETAH_CURSOR_REWARD_MANAGER");

    // ═══════════════════════════════════════════════════════════════════════════
    // TOKEN METADATA
    // ═══════════════════════════════════════════════════════════════════════════

    string private constant _NAME = "Cheetah Cursor";
    string private constant _SYMBOL = "CHC";
    uint8 private constant _DECIMALS = 18;
    uint256 public immutable maxSupply;
    uint256 public immutable genesisBlock;
    uint256 public immutable genesisTimestamp;

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE: TOKEN
    // ═══════════════════════════════════════════════════════════════════════════

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE: ROLES
    // ═══════════════════════════════════════════════════════════════════════════

    mapping(bytes32 => mapping(address => bool)) private _hasRole;
    address[] private _admins;

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE: STAKING (Cheetah speed = stake for rewards)
    // ═══════════════════════════════════════════════════════════════════════════

    uint256 public stakingLockDuration = 7 days;
    uint256 public rewardRatePerTokenPerSecond = 1e12; // scaled
    uint256 public lastRewardUpdateTimestamp;
    uint256 public rewardPerTokenStored;
    uint256 public totalStaked;

    struct StakeInfo {
        uint256 amount;
        uint256 lockedUntil;
        uint256 rewardPerTokenPaid;
        uint256 rewardsAccrued;
    }
    mapping(address => StakeInfo) public stakes;

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE: CURSOR POSITIONS (Cursor software theme)
    // ═══════════════════════════════════════════════════════════════════════════

    struct CursorPosition {
        uint256 x;
        uint256 y;
        uint256 timestamp;
    }
    mapping(address => CursorPosition) public cursorPositions;

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE: VELOCITY (Cheetah = fast)
    // ═══════════════════════════════════════════════════════════════════════════

    mapping(address => uint256[]) private _velocityHistory;
    uint256 public constant MAX_VELOCITY_HISTORY = 100;

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE: TREASURY
    // ═══════════════════════════════════════════════════════════════════════════

    uint256 public treasuryBalance;

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE: GOVERNANCE (proposals)
    // ═══════════════════════════════════════════════════════════════════════════

    uint256 public proposalCount;
    uint256 public votingPeriod = 3 days;
    uint256 public proposalThreshold = 1000 * 1e18;

    struct Proposal {
        address proposer;
        string description;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 startTime;
        uint256 endTime;
        bool executed;
    }
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    constructor(uint256 _maxSupply) {
        if (_maxSupply == 0) revert ZeroAmount();
        maxSupply = _maxSupply;
        genesisBlock = block.number;
        genesisTimestamp = block.timestamp;
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(TREASURY_ROLE, msg.sender);
        _grantRole(REWARD_MANAGER_ROLE, msg.sender);
        lastRewardUpdateTimestamp = block.timestamp;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ROLE HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    function _grantRole(bytes32 role, address account) private {
        if (account == address(0)) revert ZeroAddress();
        _hasRole[role][account] = true;
        if (role == ADMIN_ROLE) _admins.push(account);
        emit RoleGranted(role, account, msg.sender);
    }

    function _revokeRole(bytes32 role, address account) private {
        _hasRole[role][account] = false;
        emit RoleRevoked(role, account, msg.sender);
    }

    function grantRole(bytes32 role, address account) external {
        if (!_hasRole[ADMIN_ROLE][msg.sender]) revert Unauthorized();
        _grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) external {
        if (!_hasRole[ADMIN_ROLE][msg.sender]) revert Unauthorized();
        _revokeRole(role, account);
    }

    function hasRole(bytes32 role, address account) external view returns (bool) {
        return _hasRole[role][account];
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ERC-20: METADATA & BALANCE
    // ═══════════════════════════════════════════════════════════════════════════

    function name() external pure returns (string memory) {
        return _NAME;
    }

    function symbol() external pure returns (string memory) {
        return _SYMBOL;
    }

    function decimals() external pure returns (uint8) {
        return _DECIMALS;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ERC-20: TRANSFER & APPROVE
    // ═══════════════════════════════════════════════════════════════════════════

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        if (spender == address(0)) revert ZeroAddress();
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        if (currentAllowance < amount) revert InsufficientAllowance();
        unchecked {
            _allowances[from][msg.sender] = currentAllowance - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) private {
        if (from == address(0) || to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        uint256 fromBalance = _balances[from];
        if (fromBalance < amount) revert InsufficientBalance();
        unchecked {
            _balances[from] = fromBalance - amount;
            _balances[to] += amount;
        }
        emit Transfer(from, to, amount);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MINTING (restricted)
    // ═══════════════════════════════════════════════════════════════════════════

    function mint(address to, uint256 amount) external {
        if (!_hasRole[MINTER_ROLE][msg.sender]) revert Unauthorized();
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (_totalSupply + amount > maxSupply) revert MaxSupplyExceeded();
        _totalSupply += amount;
        _balances[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function burn(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        uint256 balance = _balances[msg.sender];
        if (balance < amount) revert InsufficientBalance();
        unchecked {
            _balances[msg.sender] = balance - amount;
            _totalSupply -= amount;
        }
        emit Transfer(msg.sender, address(0), amount);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REWARD MATH (staking)
    // ═══════════════════════════════════════════════════════════════════════════

    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) return rewardPerTokenStored;
        uint256 elapsed = block.timestamp - lastRewardUpdateTimestamp;
        return rewardPerTokenStored + (elapsed * rewardRatePerTokenPerSecond * 1e18) / totalStaked;
    }

    function earned(address account) public view returns (uint256) {
        StakeInfo storage s = stakes[account];
        uint256 rpt = rewardPerToken();
        uint256 pending = (s.amount * (rpt - s.rewardPerTokenPaid)) / 1e18;
        return s.rewardsAccrued + pending;
    }

    function _updateReward(address account) private {
        rewardPerTokenStored = rewardPerToken();
        lastRewardUpdateTimestamp = block.timestamp;
        if (account != address(0)) {
            StakeInfo storage s = stakes[account];
            s.rewardsAccrued = earned(account);
            s.rewardPerTokenPaid = rewardPerTokenStored;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STAKING: STAKE / UNSTAKE / CLAIM
    // ═══════════════════════════════════════════════════════════════════════════

    function stake(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        _updateReward(msg.sender);
        uint256 balance = _balances[msg.sender];
        if (balance < amount) revert InsufficientBalance();
        _transfer(msg.sender, address(this), amount);
        StakeInfo storage s = stakes[msg.sender];
        s.amount += amount;
        s.lockedUntil = block.timestamp + stakingLockDuration;
        totalStaked += amount;
        emit Staked(msg.sender, amount, s.lockedUntil);
    }

    function unstake(uint256 amount) external {
        StakeInfo storage s = stakes[msg.sender];
        if (s.amount == 0) revert NoStake();
        if (amount == 0) revert ZeroAmount();
        if (amount > s.amount) revert InsufficientBalance();
        if (block.timestamp < s.lockedUntil) revert StakingLocked();
        _updateReward(msg.sender);
        s.amount -= amount;
        totalStaked -= amount;
        _transfer(address(this), msg.sender, amount);
        emit Unstaked(msg.sender, amount);
    }

    function claimRewards() external {
        _updateReward(msg.sender);
        StakeInfo storage s = stakes[msg.sender];
        uint256 reward = s.rewardsAccrued;
        if (reward == 0) revert NoRewards();
        s.rewardsAccrued = 0;
        _mintReward(msg.sender, reward);
        emit RewardClaimed(msg.sender, reward);
    }

    function _mintReward(address to, uint256 amount) private {
        if (_totalSupply + amount > maxSupply) return; // cap at maxSupply
        _totalSupply += amount;
        _balances[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function setRewardRate(uint256 newRate) external {
        if (!_hasRole[REWARD_MANAGER_ROLE][msg.sender]) revert Unauthorized();
        _updateReward(address(0));
        rewardRatePerTokenPerSecond = newRate;
    }

    function setStakingLockDuration(uint256 newDuration) external {
        if (!_hasRole[ADMIN_ROLE][msg.sender]) revert Unauthorized();
        stakingLockDuration = newDuration;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CURSOR POSITION (Cursor software theme)
    // ═══════════════════════════════════════════════════════════════════════════

    function updateCursorPosition(uint256 x, uint256 y) external {
        cursorPositions[msg.sender] = CursorPosition({
            x: x,
            y: y,
            timestamp: block.timestamp
        });
        emit CursorPositionUpdated(msg.sender, x, y, block.timestamp);
    }

    function getCursorPosition(address account) external view returns (uint256 x, uint256 y, uint256 timestamp) {
        CursorPosition storage cp = cursorPositions[account];
        return (cp.x, cp.y, cp.timestamp);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VELOCITY (Cheetah = speed)
    // ═══════════════════════════════════════════════════════════════════════════

    function recordVelocity(uint256 velocity) external {
        uint256[] storage hist = _velocityHistory[msg.sender];
        if (hist.length >= MAX_VELOCITY_HISTORY) {
            for (uint256 i = 0; i < hist.length - 1; i++) {
                hist[i] = hist[i + 1];
            }
            hist.pop();
        }
        hist.push(velocity);
        emit VelocityRecorded(msg.sender, velocity, block.timestamp);
    }

    function getVelocityHistory(address account) external view returns (uint256[] memory) {
        return _velocityHistory[account];
    }

    function averageVelocity(address account) external view returns (uint256) {
        uint256[] storage hist = _velocityHistory[account];
        if (hist.length == 0) return 0;
        uint256 sum = 0;
        for (uint256 i = 0; i < hist.length; i++) {
