// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title CrossChainResolver
 * @dev A cross-chain resolver contract that supports Monad chain and other EVM chains
 * This contract handles cross-chain order resolution and escrow management
 */
contract CrossChainResolver is Ownable, ReentrancyGuard {
    using ECDSA for bytes32;

    // Chain IDs
    uint256 public constant MONAD_CHAIN_ID = 1337; // Replace with actual Monad chain ID
    uint256 public constant ETHEREUM_CHAIN_ID = 1;
    uint256 public constant BSC_CHAIN_ID = 56;
    uint256 public constant POLYGON_CHAIN_ID = 137;

    // Events
    event OrderCreated(
        bytes32 indexed orderHash,
        address indexed maker,
        uint256 srcChainId,
        uint256 dstChainId,
        address srcToken,
        address dstToken,
        uint256 amount,
        uint256 deadline
    );

    event OrderFilled(
        bytes32 indexed orderHash,
        address indexed taker,
        uint256 amount,
        uint256 timestamp
    );

    event OrderCancelled(
        bytes32 indexed orderHash,
        address indexed canceller,
        uint256 timestamp
    );

    event EscrowDeployed(
        bytes32 indexed orderHash,
        address indexed escrow,
        uint256 chainId,
        uint256 amount
    );

    // Structs
    struct CrossChainOrder {
        bytes32 orderHash;
        address maker;
        uint256 srcChainId;
        uint256 dstChainId;
        address srcToken;
        address dstToken;
        uint256 amount;
        uint256 deadline;
        bool isActive;
        bool isFilled;
        bool isCancelled;
    }

    struct EscrowInfo {
        address escrowAddress;
        uint256 chainId;
        uint256 amount;
        bool isDeployed;
        bool isWithdrawn;
    }

    // State variables
    mapping(bytes32 => CrossChainOrder) public orders;
    mapping(bytes32 => EscrowInfo) public escrows;
    mapping(uint256 => bool) public supportedChains;
    mapping(address => bool) public authorizedResolvers;
    
    uint256 public minOrderAmount;
    uint256 public maxOrderAmount;
    uint256 public orderTimeout;

    // Modifiers
    modifier onlyAuthorizedResolver() {
        require(authorizedResolvers[msg.sender], "CrossChainResolver: Unauthorized resolver");
        _;
    }

    modifier orderExists(bytes32 orderHash) {
        require(orders[orderHash].orderHash != bytes32(0), "CrossChainResolver: Order does not exist");
        _;
    }

    modifier orderActive(bytes32 orderHash) {
        require(orders[orderHash].isActive, "CrossChainResolver: Order is not active");
        _;
    }

    modifier orderNotExpired(bytes32 orderHash) {
        require(block.timestamp <= orders[orderHash].deadline, "CrossChainResolver: Order expired");
        _;
    }

    constructor() Ownable(msg.sender) {
        // Initialize supported chains
        supportedChains[MONAD_CHAIN_ID] = true;
        supportedChains[ETHEREUM_CHAIN_ID] = true;
        supportedChains[BSC_CHAIN_ID] = true;
        supportedChains[POLYGON_CHAIN_ID] = true;

        // Set default parameters
        minOrderAmount = 0.001 ether;
        maxOrderAmount = 1000 ether;
        orderTimeout = 1 hours;

        // Add deployer as authorized resolver
        authorizedResolvers[msg.sender] = true;
    }

    /**
     * @dev Create a new cross-chain order
     * @param srcChainId Source chain ID
     * @param dstChainId Destination chain ID
     * @param srcToken Source token address
     * @param dstToken Destination token address
     * @param amount Amount to swap
     * @param deadline Order deadline
     */
    function createOrder(
        uint256 srcChainId,
        uint256 dstChainId,
        address srcToken,
        address dstToken,
        uint256 amount,
        uint256 deadline
    ) external payable nonReentrant {
        require(supportedChains[srcChainId], "CrossChainResolver: Unsupported source chain");
        require(supportedChains[dstChainId], "CrossChainResolver: Unsupported destination chain");
        require(srcChainId != dstChainId, "CrossChainResolver: Same chain not allowed");
        require(amount >= minOrderAmount, "CrossChainResolver: Amount too low");
        require(amount <= maxOrderAmount, "CrossChainResolver: Amount too high");
        require(deadline > block.timestamp, "CrossChainResolver: Invalid deadline");
        require(msg.value >= amount, "CrossChainResolver: Insufficient payment");

        bytes32 orderHash = keccak256(abi.encodePacked(
            msg.sender,
            srcChainId,
            dstChainId,
            srcToken,
            dstToken,
            amount,
            deadline,
            block.chainid
        ));

        require(orders[orderHash].orderHash == bytes32(0), "CrossChainResolver: Order already exists");

        orders[orderHash] = CrossChainOrder({
            orderHash: orderHash,
            maker: msg.sender,
            srcChainId: srcChainId,
            dstChainId: dstChainId,
            srcToken: srcToken,
            dstToken: dstToken,
            amount: amount,
            deadline: deadline,
            isActive: true,
            isFilled: false,
            isCancelled: false
        });

        emit OrderCreated(
            orderHash,
            msg.sender,
            srcChainId,
            dstChainId,
            srcToken,
            dstToken,
            amount,
            deadline
        );
    }

    /**
     * @dev Fill a cross-chain order (only authorized resolvers)
     * @param orderHash Order hash to fill
     * @param taker Taker address
     * @param amount Amount to fill
     */
    function fillOrder(
        bytes32 orderHash,
        address taker,
        uint256 amount
    ) external onlyAuthorizedResolver orderExists(orderHash) orderActive(orderHash) orderNotExpired(orderHash) {
        CrossChainOrder storage order = orders[orderHash];
        require(!order.isFilled, "CrossChainResolver: Order already filled");
        require(amount <= order.amount, "CrossChainResolver: Amount exceeds order");

        order.isFilled = true;
        order.isActive = false;

        // Transfer funds to taker
        (bool success, ) = taker.call{value: amount}("");
        require(success, "CrossChainResolver: Transfer failed");

        emit OrderFilled(orderHash, taker, amount, block.timestamp);
    }

    /**
     * @dev Cancel an order (only maker or authorized resolver)
     * @param orderHash Order hash to cancel
     */
    function cancelOrder(bytes32 orderHash) external orderExists(orderHash) orderActive(orderHash) {
        CrossChainOrder storage order = orders[orderHash];
        require(
            msg.sender == order.maker || authorizedResolvers[msg.sender],
            "CrossChainResolver: Unauthorized to cancel"
        );

        order.isCancelled = true;
        order.isActive = false;

        // Refund maker if not filled
        if (!order.isFilled) {
            (bool success, ) = order.maker.call{value: order.amount}("");
            require(success, "CrossChainResolver: Refund failed");
        }

        emit OrderCancelled(orderHash, msg.sender, block.timestamp);
    }

    /**
     * @dev Deploy escrow on destination chain
     * @param orderHash Order hash
     * @param escrowAddress Escrow contract address
     * @param chainId Chain ID where escrow is deployed
     */
    function deployEscrow(
        bytes32 orderHash,
        address escrowAddress,
        uint256 chainId
    ) external onlyAuthorizedResolver orderExists(orderHash) {
        CrossChainOrder storage order = orders[orderHash];
        require(chainId == order.dstChainId, "CrossChainResolver: Wrong destination chain");

        escrows[orderHash] = EscrowInfo({
            escrowAddress: escrowAddress,
            chainId: chainId,
            amount: order.amount,
            isDeployed: true,
            isWithdrawn: false
        });

        emit EscrowDeployed(orderHash, escrowAddress, chainId, order.amount);
    }

    /**
     * @dev Withdraw from escrow
     * @param orderHash Order hash
     * @param recipient Recipient address
     * @param secret Secret for withdrawal
     */
    function withdrawFromEscrow(
        bytes32 orderHash,
        address recipient,
        bytes32 secret
    ) external onlyAuthorizedResolver orderExists(orderHash) {
        EscrowInfo storage escrow = escrows[orderHash];
        require(escrow.isDeployed, "CrossChainResolver: Escrow not deployed");
        require(!escrow.isWithdrawn, "CrossChainResolver: Already withdrawn");

        escrow.isWithdrawn = true;

        // Transfer funds to recipient
        (bool success, ) = recipient.call{value: escrow.amount}("");
        require(success, "CrossChainResolver: Withdrawal failed");
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
     * @dev Add or remove supported chain
     * @param chainId Chain ID
     * @param isSupported Support status
     */
    function setSupportedChain(uint256 chainId, bool isSupported) external onlyOwner {
        supportedChains[chainId] = isSupported;
    }

    /**
     * @dev Update order parameters
     * @param _minOrderAmount Minimum order amount
     * @param _maxOrderAmount Maximum order amount
     * @param _orderTimeout Order timeout
     */
    function updateOrderParameters(
        uint256 _minOrderAmount,
        uint256 _maxOrderAmount,
        uint256 _orderTimeout
    ) external onlyOwner {
        minOrderAmount = _minOrderAmount;
        maxOrderAmount = _maxOrderAmount;
        orderTimeout = _orderTimeout;
    }

    /**
     * @dev Get order details
     * @param orderHash Order hash
     * @return Order details
     */
    function getOrder(bytes32 orderHash) external view returns (CrossChainOrder memory) {
        return orders[orderHash];
    }

    /**
     * @dev Get escrow details
     * @param orderHash Order hash
     * @return Escrow details
     */
    function getEscrow(bytes32 orderHash) external view returns (EscrowInfo memory) {
        return escrows[orderHash];
    }

    /**
     * @dev Check if chain is supported
     * @param chainId Chain ID
     * @return True if supported
     */
    function isChainSupported(uint256 chainId) external view returns (bool) {
        return supportedChains[chainId];
    }

    /**
     * @dev Emergency withdraw (only owner)
     */
    function emergencyWithdraw() external onlyOwner {
        (bool success, ) = owner().call{value: address(this).balance}("");
        require(success, "CrossChainResolver: Emergency withdrawal failed");
    }

    // Receive function to accept ETH
    receive() external payable {}
} 