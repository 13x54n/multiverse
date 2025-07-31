// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/utils/Create2.sol";

/**
 * @title MonadFusionPlusResolver
 * @dev Novel 1inch Fusion+ extension for Ethereum-Monad cross-chain swaps
 * Features:
 * - Bidirectional swaps between Ethereum and Monad
 * - Hashlock and timelock functionality
 * - Partial fill support
 * - Enhanced security with multiple validation layers
 */
contract MonadFusionPlusResolver is Ownable, ReentrancyGuard {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;

    // Chain IDs
    uint256 public constant ETHEREUM_CHAIN_ID = 1;
    uint256 public constant MONAD_CHAIN_ID = 1337; // Replace with actual Monad chain ID

    // Events
    event FusionOrderCreated(
        bytes32 indexed orderHash,
        address indexed maker,
        uint256 srcChainId,
        uint256 dstChainId,
        address srcToken,
        address dstToken,
        uint256 amount,
        uint256 deadline,
        bytes32 hashlock,
        uint256 timelock
    );

    event FusionOrderFilled(
        bytes32 indexed orderHash,
        address indexed taker,
        uint256 amount,
        bytes32 secret,
        uint256 timestamp
    );

    event FusionOrderCancelled(
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

    event PartialFill(
        bytes32 indexed orderHash,
        address indexed taker,
        uint256 partialAmount,
        uint256 remainingAmount
    );

    // Structs
    struct FusionOrder {
        bytes32 orderHash;
        address maker;
        uint256 srcChainId;
        uint256 dstChainId;
        address srcToken;
        address dstToken;
        uint256 amount;
        uint256 deadline;
        bytes32 hashlock;
        uint256 timelock;
        bool isActive;
        bool isFilled;
        bool isCancelled;
        uint256 filledAmount;
        uint256 remainingAmount;
    }

    struct EscrowInfo {
        address escrowAddress;
        uint256 chainId;
        uint256 amount;
        bool isDeployed;
        bool isWithdrawn;
        bytes32 secret;
    }

    struct SwapParams {
        uint256 srcChainId;
        uint256 dstChainId;
        address srcToken;
        address dstToken;
        uint256 amount;
        uint256 deadline;
        bytes32 hashlock;
        uint256 timelock;
        address recipient;
    }

    // State variables
    mapping(bytes32 => FusionOrder) public fusionOrders;
    mapping(bytes32 => EscrowInfo) public escrows;
    mapping(uint256 => bool) public supportedChains;
    mapping(address => bool) public authorizedResolvers;
    mapping(bytes32 => mapping(address => uint256)) public partialFills;
    
    uint256 public minOrderAmount;
    uint256 public maxOrderAmount;
    uint256 public orderTimeout;
    uint256 public safetyDeposit;
    uint256 public resolverFee;

    // Implementation addresses for escrow clones
    address public escrowSrcImplementation;
    address public escrowDstImplementation;

    // Modifiers
    modifier onlyAuthorizedResolver() {
        require(authorizedResolvers[msg.sender], "MonadFusionPlusResolver: Unauthorized resolver");
        _;
    }

    modifier orderExists(bytes32 orderHash) {
        require(fusionOrders[orderHash].orderHash != bytes32(0), "MonadFusionPlusResolver: Order does not exist");
        _;
    }

    modifier orderActive(bytes32 orderHash) {
        require(fusionOrders[orderHash].isActive, "MonadFusionPlusResolver: Order is not active");
        _;
    }

    modifier orderNotExpired(bytes32 orderHash) {
        require(block.timestamp <= fusionOrders[orderHash].deadline, "MonadFusionPlusResolver: Order expired");
        _;
    }

    modifier validChainPair(uint256 srcChainId, uint256 dstChainId) {
        require(
            (srcChainId == ETHEREUM_CHAIN_ID && dstChainId == MONAD_CHAIN_ID) ||
            (srcChainId == MONAD_CHAIN_ID && dstChainId == ETHEREUM_CHAIN_ID),
            "MonadFusionPlusResolver: Invalid chain pair"
        );
        _;
    }

    modifier validAmount(uint256 amount) {
        require(amount >= minOrderAmount && amount <= maxOrderAmount, "MonadFusionPlusResolver: Invalid amount");
        _;
    }

    constructor() Ownable(msg.sender) {
        minOrderAmount = 0.001 ether;
        maxOrderAmount = 1000 ether;
        orderTimeout = 1 hours;
        safetyDeposit = 0.01 ether;
        resolverFee = 0.001 ether;
        
        supportedChains[ETHEREUM_CHAIN_ID] = true;
        supportedChains[MONAD_CHAIN_ID] = true;
        
        authorizedResolvers[msg.sender] = true;
    }

    /**
     * @dev Create a new Fusion+ cross-chain order
     * @param params Swap parameters
     */
    function createFusionOrder(SwapParams calldata params) 
        external 
        payable 
        nonReentrant 
        validChainPair(params.srcChainId, params.dstChainId)
        validAmount(params.amount)
    {
        require(msg.value >= params.amount + safetyDeposit, "MonadFusionPlusResolver: Insufficient value");
        require(params.deadline > block.timestamp, "MonadFusionPlusResolver: Invalid deadline");
        require(params.timelock > 0, "MonadFusionPlusResolver: Invalid timelock");

        bytes32 orderHash = _computeOrderHash(params);
        
        require(fusionOrders[orderHash].orderHash == bytes32(0), "MonadFusionPlusResolver: Order already exists");

        FusionOrder memory newOrder = FusionOrder({
            orderHash: orderHash,
            maker: msg.sender,
            srcChainId: params.srcChainId,
            dstChainId: params.dstChainId,
            srcToken: params.srcToken,
            dstToken: params.dstToken,
            amount: params.amount,
            deadline: params.deadline,
            hashlock: params.hashlock,
            timelock: params.timelock,
            isActive: true,
            isFilled: false,
            isCancelled: false,
            filledAmount: 0,
            remainingAmount: params.amount
        });

        fusionOrders[orderHash] = newOrder;

        emit FusionOrderCreated(
            orderHash,
            msg.sender,
            params.srcChainId,
            params.dstChainId,
            params.srcToken,
            params.dstToken,
            params.amount,
            params.deadline,
            params.hashlock,
            params.timelock
        );
    }

    /**
     * @dev Fill a Fusion+ order (authorized resolvers only)
     * @param orderHash Order hash
     * @param takerAddress Taker address
     * @param amount Amount to fill
     * @param secret Secret to unlock the escrow
     */
    function fillFusionOrder(
        bytes32 orderHash,
        address takerAddress,
        uint256 amount,
        bytes32 secret
    ) 
        external 
        onlyAuthorizedResolver 
        orderExists(orderHash) 
        orderActive(orderHash) 
        orderNotExpired(orderHash)
    {
        FusionOrder storage order = fusionOrders[orderHash];
        
        require(amount <= order.remainingAmount, "MonadFusionPlusResolver: Amount exceeds remaining");
        require(_verifySecret(secret, order.hashlock), "MonadFusionPlusResolver: Invalid secret");

        // Update order state
        order.filledAmount += amount;
        order.remainingAmount -= amount;
        partialFills[orderHash][takerAddress] += amount;

        if (order.remainingAmount == 0) {
            order.isActive = false;
            order.isFilled = true;
        }

        // Deploy escrow on destination chain
        _deployEscrow(orderHash, order, amount, secret);

        // Transfer tokens to taker
        if (order.srcToken == address(0)) {
            payable(takerAddress).transfer(amount);
        } else {
            IERC20(order.srcToken).safeTransfer(takerAddress, amount);
        }

        emit FusionOrderFilled(orderHash, takerAddress, amount, secret, block.timestamp);
        
        if (order.remainingAmount > 0) {
            emit PartialFill(orderHash, takerAddress, amount, order.remainingAmount);
        }
    }

    /**
     * @dev Cancel a Fusion+ order
     * @param orderHash Order hash
     */
    function cancelFusionOrder(bytes32 orderHash) 
        external 
        orderExists(orderHash) 
        orderActive(orderHash)
    {
        FusionOrder storage order = fusionOrders[orderHash];
        
        require(
            msg.sender == order.maker || 
            (block.timestamp > order.deadline + order.timelock),
            "MonadFusionPlusResolver: Cannot cancel order"
        );

        order.isActive = false;
        order.isCancelled = true;

        // Refund maker
        uint256 refundAmount = order.remainingAmount + safetyDeposit;
        if (order.srcToken == address(0)) {
            payable(order.maker).transfer(refundAmount);
        } else {
            IERC20(order.srcToken).safeTransfer(order.maker, refundAmount);
        }

        emit FusionOrderCancelled(orderHash, msg.sender, block.timestamp);
    }

    /**
     * @dev Withdraw from escrow using secret
     * @param orderHash Order hash
     * @param secret Secret to unlock escrow
     */
    function withdrawFromEscrow(bytes32 orderHash, bytes32 secret) 
        external 
        nonReentrant
    {
        EscrowInfo storage escrow = escrows[orderHash];
        require(escrow.isDeployed, "MonadFusionPlusResolver: Escrow not deployed");
        require(!escrow.isWithdrawn, "MonadFusionPlusResolver: Already withdrawn");

        FusionOrder memory order = fusionOrders[orderHash];
        require(_verifySecret(secret, order.hashlock), "MonadFusionPlusResolver: Invalid secret");

        escrow.isWithdrawn = true;
        escrow.secret = secret;

        // Transfer tokens to recipient
        if (order.dstToken == address(0)) {
            payable(msg.sender).transfer(escrow.amount);
        } else {
            IERC20(order.dstToken).safeTransfer(msg.sender, escrow.amount);
        }
    }

    /**
     * @dev Deploy escrow on destination chain
     * @param orderHash Order hash
     * @param order Order details
     * @param amount Amount for escrow
     * @param secret Secret for escrow
     */
    function _deployEscrow(
        bytes32 orderHash,
        FusionOrder memory order,
        uint256 amount,
        bytes32 secret
    ) internal {
        bytes32 salt = keccak256(abi.encodePacked(orderHash, secret));
        address escrowAddress = Create2.computeAddress(
            salt,
            keccak256(type(EscrowDst).creationCode),
            address(this)
        );

        EscrowDst escrow = new EscrowDst{salt: salt}(
            order.dstToken,
            amount,
            order.maker,
            order.hashlock,
            order.timelock
        );

        escrows[orderHash] = EscrowInfo({
            escrowAddress: address(escrow),
            chainId: order.dstChainId,
            amount: amount,
            isDeployed: true,
            isWithdrawn: false,
            secret: bytes32(0)
        });

        emit EscrowDeployed(orderHash, address(escrow), order.dstChainId, amount);
    }

    /**
     * @dev Compute order hash
     * @param params Swap parameters
     * @return Order hash
     */
    function _computeOrderHash(SwapParams calldata params) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(
            params.srcChainId,
            params.dstChainId,
            params.srcToken,
            params.dstToken,
            params.amount,
            params.deadline,
            params.hashlock,
            params.timelock,
            msg.sender,
            block.chainid
        ));
    }

    /**
     * @dev Verify secret against hashlock
     * @param secret Secret to verify
     * @param hashlock Hashlock to verify against
     * @return True if secret is valid
     */
    function _verifySecret(bytes32 secret, bytes32 hashlock) internal pure returns (bool) {
        return keccak256(abi.encodePacked(secret)) == hashlock;
    }

    // Admin functions
    function setAuthorizedResolver(address resolver, bool authorized) external onlyOwner {
        authorizedResolvers[resolver] = authorized;
    }

    function updateOrderParameters(
        uint256 _minOrderAmount,
        uint256 _maxOrderAmount,
        uint256 _orderTimeout
    ) external onlyOwner {
        minOrderAmount = _minOrderAmount;
        maxOrderAmount = _maxOrderAmount;
        orderTimeout = _orderTimeout;
    }

    function updateFees(uint256 _safetyDeposit, uint256 _resolverFee) external onlyOwner {
        safetyDeposit = _safetyDeposit;
        resolverFee = _resolverFee;
    }

    function withdrawFees() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    // View functions
    function getFusionOrder(bytes32 orderHash) external view returns (FusionOrder memory) {
        return fusionOrders[orderHash];
    }

    function getEscrowInfo(bytes32 orderHash) external view returns (EscrowInfo memory) {
        return escrows[orderHash];
    }

    function getPartialFill(bytes32 orderHash, address taker) external view returns (uint256) {
        return partialFills[orderHash][taker];
    }

    function isOrderActive(bytes32 orderHash) external view returns (bool) {
        return fusionOrders[orderHash].isActive;
    }

    function isOrderExpired(bytes32 orderHash) external view returns (bool) {
        return block.timestamp > fusionOrders[orderHash].deadline;
    }

    // Emergency functions
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            payable(owner()).transfer(amount);
        } else {
            IERC20(token).safeTransfer(owner(), amount);
        }
    }

    receive() external payable {}
} 