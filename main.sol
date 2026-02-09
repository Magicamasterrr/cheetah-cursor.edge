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
