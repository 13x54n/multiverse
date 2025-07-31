// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title Escrow
 * @dev Escrow contract for cross-chain deposits and withdrawals
 * Supports Monad chain and other EVM chains
 */
contract Escrow is Ownable, ReentrancyGuard {
    using ECDSA for bytes32;

    // Events
    event Deposit(
        bytes32 indexed orderHash,
        address indexed depositor,
        uint256 amount,
        uint256 timestamp
    );

    event Withdrawal(
        bytes32 indexed orderHash,
        address indexed recipient,
        uint256 amount,
        bytes32 secret,
        uint256 timestamp
    );

    event Cancellation(
        bytes32 indexed orderHash,
        address indexed canceller,
        uint256 timestamp
    );

    // Structs
    struct EscrowData {
        bytes32 orderHash;
        address depositor;
        address recipient;
        uint256 amount;
        uint256 deadline;
        bytes32 secretHash;
        bool isActive;
        bool isWithdrawn;
        bool isCancelled;
    }

    // State variables
    mapping(bytes32 => EscrowData) public escrows;
    mapping(address => bool) public authorizedResolvers;
    
    uint256 public minDepositAmount;
    uint256 public maxDepositAmount;
    uint256 public escrowTimeout;

    // Modifiers
    modifier onlyAuthorizedResolver() {
        require(authorizedResolvers[msg.sender], "Escrow: Unauthorized resolver");
        _;
    }

    modifier escrowExists(bytes32 orderHash) {
        require(escrows[orderHash].orderHash != bytes32(0), "Escrow: Escrow does not exist");
        _;
    }

    modifier escrowActive(bytes32 orderHash) {
        require(escrows[orderHash].isActive, "Escrow: Escrow is not active");
        _;
    }

    modifier escrowNotExpired(bytes32 orderHash) {
        require(block.timestamp <= escrows[orderHash].deadline, "Escrow: Escrow expired");
        _;
    }

    constructor() Ownable(msg.sender) {
        minDepositAmount = 0.001 ether;
        maxDepositAmount = 1000 ether;
        escrowTimeout = 1 hours;
        
        authorizedResolvers[msg.sender] = true;
    }

    /**
     * @dev Create escrow deposit
     * @param orderHash Order hash
     * @param recipient Recipient address
     * @param secretHash Hash of the secret
     * @param deadline Escrow deadline
     */
    function createEscrow(
        bytes32 orderHash,
        address recipient,
        bytes32 secretHash,
        uint256 deadline
    ) external payable nonReentrant {
        require(escrows[orderHash].orderHash == bytes32(0), "Escrow: Escrow already exists");
        require(msg.value >= minDepositAmount, "Escrow: Amount too low");
        require(msg.value <= maxDepositAmount, "Escrow: Amount too high");
        require(deadline > block.timestamp, "Escrow: Invalid deadline");
        require(recipient != address(0), "Escrow: Invalid recipient");

        escrows[orderHash] = EscrowData({
            orderHash: orderHash,
            depositor: msg.sender,
            recipient: recipient,
            amount: msg.value,
            deadline: deadline,
            secretHash: secretHash,
            isActive: true,
            isWithdrawn: false,
            isCancelled: false
        });

        emit Deposit(orderHash, msg.sender, msg.value, block.timestamp);
    }

    /**
     * @dev Withdraw from escrow using secret
     * @param orderHash Order hash
     * @param secret Secret for withdrawal
     */
    function withdraw(
        bytes32 orderHash,
        bytes32 secret
    ) external escrowExists(orderHash) escrowActive(orderHash) escrowNotExpired(orderHash) nonReentrant {
        EscrowData storage escrow = escrows[orderHash];
        require(!escrow.isWithdrawn, "Escrow: Already withdrawn");
        require(!escrow.isCancelled, "Escrow: Escrow cancelled");
        require(keccak256(abi.encodePacked(secret)) == escrow.secretHash, "Escrow: Invalid secret");
        require(msg.sender == escrow.recipient, "Escrow: Unauthorized withdrawal");

        escrow.isWithdrawn = true;
        escrow.isActive = false;

        (bool success, ) = escrow.recipient.call{value: escrow.amount}("");
        require(success, "Escrow: Withdrawal failed");

        emit Withdrawal(orderHash, escrow.recipient, escrow.amount, secret, block.timestamp);
    }

    /**
     * @dev Cancel escrow (only depositor or authorized resolver)
     * @param orderHash Order hash
     */
    function cancelEscrow(bytes32 orderHash) external escrowExists(orderHash) escrowActive(orderHash) {
        EscrowData storage escrow = escrows[orderHash];
        require(
            msg.sender == escrow.depositor || authorizedResolvers[msg.sender],
            "Escrow: Unauthorized to cancel"
        );
        require(!escrow.isWithdrawn, "Escrow: Already withdrawn");

        escrow.isCancelled = true;
        escrow.isActive = false;

        // Refund depositor
        (bool success, ) = escrow.depositor.call{value: escrow.amount}("");
        require(success, "Escrow: Refund failed");

        emit Cancellation(orderHash, msg.sender, block.timestamp);
    }

    /**
     * @dev Force withdraw (only authorized resolver)
     * @param orderHash Order hash
     * @param recipient Recipient address
     */
    function forceWithdraw(
        bytes32 orderHash,
        address recipient
    ) external onlyAuthorizedResolver escrowExists(orderHash) escrowActive(orderHash) nonReentrant {
        EscrowData storage escrow = escrows[orderHash];
        require(!escrow.isWithdrawn, "Escrow: Already withdrawn");
        require(!escrow.isCancelled, "Escrow: Escrow cancelled");

        escrow.isWithdrawn = true;
        escrow.isActive = false;

        (bool success, ) = recipient.call{value: escrow.amount}("");
        require(success, "Escrow: Force withdrawal failed");

        emit Withdrawal(orderHash, recipient, escrow.amount, bytes32(0), block.timestamp);
    }

    /**
     * @dev Get escrow details
     * @param orderHash Order hash
     * @return Escrow details
     */
    function getEscrow(bytes32 orderHash) external view returns (EscrowData memory) {
        return escrows[orderHash];
    }

    /**
     * @dev Add or remove authorized resolver
     * @param resolver Resolver address
     * @param isAuthorized Authorization status
     */
    function setAuthorizedResolver(address resolver, bool isAuthorized) external onlyOwner {
        authorizedResolvers[resolver] = isAuthorized;
    }

    /**
     * @dev Update escrow parameters
     * @param _minDepositAmount Minimum deposit amount
     * @param _maxDepositAmount Maximum deposit amount
     * @param _escrowTimeout Escrow timeout
     */
    function updateEscrowParameters(
        uint256 _minDepositAmount,
        uint256 _maxDepositAmount,
        uint256 _escrowTimeout
    ) external onlyOwner {
        minDepositAmount = _minDepositAmount;
        maxDepositAmount = _maxDepositAmount;
        escrowTimeout = _escrowTimeout;
    }

    /**
     * @dev Emergency withdraw (only owner)
     */
    function emergencyWithdraw() external onlyOwner {
        (bool success, ) = owner().call{value: address(this).balance}("");
        require(success, "Escrow: Emergency withdrawal failed");
    }

    // Receive function to accept ETH
    receive() external payable {}
} 