// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title FusionPlusEscrowDst
 * @dev Destination escrow contract for 1inch Fusion+ cross-chain swaps
 * Enhanced with hashlock and timelock functionality
 */
contract FusionPlusEscrowDst is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Events
    event EscrowCreated(
        bytes32 indexed orderHash,
        address indexed maker,
        address token,
        uint256 amount,
        bytes32 hashlock,
        uint256 timelock
    );

    event Withdrawal(
        bytes32 indexed orderHash,
        address indexed recipient,
        uint256 amount,
        bytes32 secret
    );

    event Cancellation(
        bytes32 indexed orderHash,
        address indexed canceller,
        uint256 amount
    );

    // Structs
    struct EscrowData {
        bytes32 orderHash;
        address maker;
        address token;
        uint256 amount;
        bytes32 hashlock;
        uint256 timelock;
        uint256 createdAt;
        bool isActive;
        bool isWithdrawn;
        bool isCancelled;
    }

    // State variables
    mapping(bytes32 => EscrowData) public escrows;
    mapping(address => bool) public authorizedResolvers;
    
    uint256 public minDepositAmount;
    uint256 public maxDepositAmount;
    uint256 public defaultTimelock;

    // Modifiers
    modifier onlyAuthorizedResolver() {
        require(authorizedResolvers[msg.sender], "FusionPlusEscrowDst: Unauthorized resolver");
        _;
    }

    modifier escrowExists(bytes32 orderHash) {
        require(escrows[orderHash].orderHash != bytes32(0), "FusionPlusEscrowDst: Escrow does not exist");
        _;
    }

    modifier escrowActive(bytes32 orderHash) {
        require(escrows[orderHash].isActive, "FusionPlusEscrowDst: Escrow is not active");
        _;
    }

    modifier escrowNotExpired(bytes32 orderHash) {
        EscrowData memory escrow = escrows[orderHash];
        require(
            block.timestamp <= escrow.createdAt + escrow.timelock,
            "FusionPlusEscrowDst: Escrow expired"
        );
        _;
    }

    modifier validSecret(bytes32 secret, bytes32 hashlock) {
        require(keccak256(abi.encodePacked(secret)) == hashlock, "FusionPlusEscrowDst: Invalid secret");
        _;
    }

    constructor() Ownable(msg.sender) {
        minDepositAmount = 0.001 ether;
        maxDepositAmount = 1000 ether;
        defaultTimelock = 1 hours;
        
        authorizedResolvers[msg.sender] = true;
    }

    /**
     * @dev Create escrow deposit (called by resolver)
     * @param orderHash Order hash
     * @param token Token address (address(0) for native)
     * @param amount Amount to deposit
     * @param hashlock Hash of the secret
     * @param timelock Timelock duration
     */
    function createEscrow(
        bytes32 orderHash,
        address token,
        uint256 amount,
        bytes32 hashlock,
        uint256 timelock
    ) external payable onlyAuthorizedResolver nonReentrant {
        require(amount >= minDepositAmount && amount <= maxDepositAmount, "FusionPlusEscrowDst: Invalid amount");
        require(escrows[orderHash].orderHash == bytes32(0), "FusionPlusEscrowDst: Escrow already exists");
        require(timelock > 0, "FusionPlusEscrowDst: Invalid timelock");

        if (token == address(0)) {
            require(msg.value == amount, "FusionPlusEscrowDst: Incorrect native amount");
        } else {
            require(msg.value == 0, "FusionPlusEscrowDst: Native tokens not expected");
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        escrows[orderHash] = EscrowData({
            orderHash: orderHash,
            maker: msg.sender,
            token: token,
            amount: amount,
            hashlock: hashlock,
            timelock: timelock,
            createdAt: block.timestamp,
            isActive: true,
            isWithdrawn: false,
            isCancelled: false
        });

        emit EscrowCreated(orderHash, msg.sender, token, amount, hashlock, timelock);
    }

    /**
     * @dev Withdraw from escrow using secret
     * @param orderHash Order hash
     * @param secret Secret to unlock escrow
     * @param recipient Recipient address
     */
    function withdraw(
        bytes32 orderHash,
        bytes32 secret,
        address recipient
    ) 
        external 
        escrowExists(orderHash) 
        escrowActive(orderHash) 
        escrowNotExpired(orderHash)
        validSecret(secret, escrows[orderHash].hashlock)
    {
        EscrowData storage escrow = escrows[orderHash];
        
        escrow.isActive = false;
        escrow.isWithdrawn = true;

        _transferTokens(escrow.token, recipient, escrow.amount);

        emit Withdrawal(orderHash, recipient, escrow.amount, secret);
    }

    /**
     * @dev Cancel escrow (only after timelock expires)
     * @param orderHash Order hash
     */
    function cancelEscrow(bytes32 orderHash) 
        external 
        onlyAuthorizedResolver 
        escrowExists(orderHash) 
        escrowActive(orderHash)
    {
        EscrowData storage escrow = escrows[orderHash];
        
        require(
            block.timestamp > escrow.createdAt + escrow.timelock,
            "FusionPlusEscrowDst: Cannot cancel yet"
        );

        escrow.isActive = false;
        escrow.isCancelled = true;

        _transferTokens(escrow.token, escrow.maker, escrow.amount);

        emit Cancellation(orderHash, msg.sender, escrow.amount);
    }

    /**
     * @dev Public withdrawal after timelock expires
     * @param orderHash Order hash
     * @param secret Secret to unlock escrow
     */
    function publicWithdraw(
        bytes32 orderHash,
        bytes32 secret
    ) 
        external 
        escrowExists(orderHash) 
        escrowActive(orderHash)
        validSecret(secret, escrows[orderHash].hashlock)
    {
        EscrowData storage escrow = escrows[orderHash];
        
        require(
            block.timestamp > escrow.createdAt + escrow.timelock,
            "FusionPlusEscrowDst: Timelock not expired"
        );

        escrow.isActive = false;
        escrow.isWithdrawn = true;

        _transferTokens(escrow.token, msg.sender, escrow.amount);

        emit Withdrawal(orderHash, msg.sender, escrow.amount, secret);
    }

    /**
     * @dev Transfer tokens (ERC20 or native)
     * @param token Token address
     * @param to Recipient
     * @param amount Amount
     */
    function _transferTokens(address token, address to, uint256 amount) internal {
        if (token == address(0)) {
            payable(to).transfer(amount);
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    // Admin functions
    function setAuthorizedResolver(address resolver, bool authorized) external onlyOwner {
        authorizedResolvers[resolver] = authorized;
    }

    function updateParameters(
        uint256 _minDepositAmount,
        uint256 _maxDepositAmount,
        uint256 _defaultTimelock
    ) external onlyOwner {
        minDepositAmount = _minDepositAmount;
        maxDepositAmount = _maxDepositAmount;
        defaultTimelock = _defaultTimelock;
    }

    // View functions
    function getEscrow(bytes32 orderHash) external view returns (EscrowData memory) {
        return escrows[orderHash];
    }

    function isEscrowActive(bytes32 orderHash) external view returns (bool) {
        return escrows[orderHash].isActive;
    }

    function isEscrowExpired(bytes32 orderHash) external view returns (bool) {
        EscrowData memory escrow = escrows[orderHash];
        return block.timestamp > escrow.createdAt + escrow.timelock;
    }

    // Emergency functions
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        _transferTokens(token, owner(), amount);
    }

    receive() external payable {}
} 