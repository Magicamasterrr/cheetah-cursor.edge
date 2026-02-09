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
