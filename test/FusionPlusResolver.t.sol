// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../src/MonadFusionPlusResolver.sol";
import "../src/FusionPlusEscrowSrc.sol";
import "../src/FusionPlusEscrowDst.sol";
import "../src/EscrowDst.sol";

/**
 * @title FusionPlusResolverTest
 * @dev Comprehensive test suite for 1inch Fusion+ cross-chain swap system
 * Tests hashlock, timelock, bidirectional swaps, and onchain execution
 */
contract FusionPlusResolverTest is Test {
    MonadFusionPlusResolver public resolver;
    FusionPlusEscrowSrc public escrowSrc;
    FusionPlusEscrowDst public escrowDst;
    EscrowDst public escrowDstImpl;
    
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    address public resolverAddress = address(0x4);
    
    uint256 public constant ETHEREUM_CHAIN_ID = 1;
    uint256 public constant MONAD_CHAIN_ID = 1337;
    
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

    event EscrowDeployed(
        bytes32 indexed orderHash,
        address indexed escrow,
        uint256 chainId,
        uint256 amount
    );

    function setUp() public {
        // Deploy contracts
        resolver = new MonadFusionPlusResolver();
        escrowSrc = new FusionPlusEscrowSrc();
        escrowDst = new FusionPlusEscrowDst();
        escrowDstImpl = new EscrowDst(
            address(0), // placeholder
            0,          // placeholder
            address(0), // placeholder
            bytes32(0), // placeholder
            0           // placeholder
        );
        
        // Set up cross-references
        resolver.setAuthorizedResolver(address(escrowSrc), true);
        resolver.setAuthorizedResolver(address(escrowDst), true);
        resolver.setAuthorizedResolver(resolverAddress, true);
        
        escrowSrc.setAuthorizedResolver(address(resolver), true);
        escrowDst.setAuthorizedResolver(address(resolver), true);
        
        // Fund test accounts
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
        vm.deal(resolverAddress, 100 ether);
    }

    function testCreateFusionOrderEthereumToMonad() public {
        vm.startPrank(alice);
        
        uint256 amount = 1 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 timelock = 30 minutes;
        bytes32 secret = keccak256(abi.encodePacked("test-secret"));
        bytes32 hashlock = keccak256(abi.encodePacked(secret));
        
        MonadFusionPlusResolver.SwapParams memory params = MonadFusionPlusResolver.SwapParams({
            srcChainId: ETHEREUM_CHAIN_ID,
            dstChainId: MONAD_CHAIN_ID,
            srcToken: address(0), // ETH
            dstToken: address(0x123), // Monad token
            amount: amount,
            deadline: deadline,
            hashlock: hashlock,
            timelock: timelock,
            recipient: bob
        });

        vm.expectEmit(true, true, false, true);
        emit FusionOrderCreated(
            bytes32(0), // We'll calculate this
            alice,
            ETHEREUM_CHAIN_ID,
            MONAD_CHAIN_ID,
            address(0),
            address(0x123),
            amount,
            deadline,
            hashlock,
            timelock
        );

        resolver.createFusionOrder{value: amount + 0.01 ether}(params);
        
        vm.stopPrank();
    }

    function testCreateFusionOrderMonadToEthereum() public {
        vm.startPrank(bob);
        
        uint256 amount = 0.5 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 timelock = 30 minutes;
        bytes32 secret = keccak256(abi.encodePacked("test-secret-2"));
        bytes32 hashlock = keccak256(abi.encodePacked(secret));
        
        MonadFusionPlusResolver.SwapParams memory params = MonadFusionPlusResolver.SwapParams({
            srcChainId: MONAD_CHAIN_ID,
            dstChainId: ETHEREUM_CHAIN_ID,
            srcToken: address(0x456), // Monad token
            dstToken: address(0), // ETH
            amount: amount,
            deadline: deadline,
            hashlock: hashlock,
            timelock: timelock,
            recipient: alice
        });

        resolver.createFusionOrder{value: amount + 0.01 ether}(params);
        
        vm.stopPrank();
    }

    function testFillFusionOrderWithHashlock() public {
        // Create order
        vm.startPrank(alice);
        uint256 amount = 1 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 timelock = 30 minutes;
        bytes32 secret = keccak256(abi.encodePacked("test-secret-3"));
        bytes32 hashlock = keccak256(abi.encodePacked(secret));
        
        MonadFusionPlusResolver.SwapParams memory params = MonadFusionPlusResolver.SwapParams({
            srcChainId: ETHEREUM_CHAIN_ID,
            dstChainId: MONAD_CHAIN_ID,
            srcToken: address(0),
            dstToken: address(0x123),
            amount: amount,
            deadline: deadline,
            hashlock: hashlock,
            timelock: timelock,
            recipient: bob
        });

        resolver.createFusionOrder{value: amount + 0.01 ether}(params);
        vm.stopPrank();
        
        // Get order hash
        bytes32 orderHash = resolver._computeOrderHash(params);
        
        // Fill order with correct secret
        vm.startPrank(resolverAddress);
        uint256 balanceBefore = charlie.balance;
        
        vm.expectEmit(true, true, false, true);
        emit FusionOrderFilled(orderHash, charlie, amount, secret, block.timestamp);
        
        resolver.fillFusionOrder(orderHash, charlie, amount, secret);
        
        uint256 balanceAfter = charlie.balance;
        assertEq(balanceAfter - balanceBefore, amount);
        vm.stopPrank();
    }

    function testPartialFillSupport() public {
        // Create order
        vm.startPrank(alice);
        uint256 totalAmount = 2 ether;
        uint256 partialAmount1 = 0.5 ether;
        uint256 partialAmount2 = 0.3 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 timelock = 30 minutes;
        bytes32 secret = keccak256(abi.encodePacked("test-secret-4"));
        bytes32 hashlock = keccak256(abi.encodePacked(secret));
        
        MonadFusionPlusResolver.SwapParams memory params = MonadFusionPlusResolver.SwapParams({
            srcChainId: ETHEREUM_CHAIN_ID,
            dstChainId: MONAD_CHAIN_ID,
            srcToken: address(0),
            dstToken: address(0x123),
            amount: totalAmount,
            deadline: deadline,
            hashlock: hashlock,
            timelock: timelock,
            recipient: bob
        });

        resolver.createFusionOrder{value: totalAmount + 0.01 ether}(params);
        vm.stopPrank();
        
        bytes32 orderHash = resolver._computeOrderHash(params);
        
        // First partial fill
        vm.startPrank(resolverAddress);
        resolver.fillFusionOrder(orderHash, charlie, partialAmount1, secret);
        
        MonadFusionPlusResolver.FusionOrder memory order = resolver.getFusionOrder(orderHash);
        assertEq(order.filledAmount, partialAmount1);
        assertEq(order.remainingAmount, totalAmount - partialAmount1);
        assertTrue(order.isActive);
        
        // Second partial fill
        resolver.fillFusionOrder(orderHash, bob, partialAmount2, secret);
        
        order = resolver.getFusionOrder(orderHash);
        assertEq(order.filledAmount, partialAmount1 + partialAmount2);
        assertEq(order.remainingAmount, totalAmount - partialAmount1 - partialAmount2);
        vm.stopPrank();
    }

    function testTimelockEnforcement() public {
        // Create order
        vm.startPrank(alice);
        uint256 amount = 1 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 timelock = 30 minutes;
        bytes32 secret = keccak256(abi.encodePacked("test-secret-5"));
        bytes32 hashlock = keccak256(abi.encodePacked(secret));
        
        MonadFusionPlusResolver.SwapParams memory params = MonadFusionPlusResolver.SwapParams({
            srcChainId: ETHEREUM_CHAIN_ID,
            dstChainId: MONAD_CHAIN_ID,
            srcToken: address(0),
            dstToken: address(0x123),
            amount: amount,
            deadline: deadline,
            hashlock: hashlock,
            timelock: timelock,
            recipient: bob
        });

        resolver.createFusionOrder{value: amount + 0.01 ether}(params);
        vm.stopPrank();
        
        bytes32 orderHash = resolver._computeOrderHash(params);
        
        // Try to cancel before timelock expires (should fail)
        vm.startPrank(alice);
        vm.expectRevert("MonadFusionPlusResolver: Cannot cancel order");
        resolver.cancelFusionOrder(orderHash);
        vm.stopPrank();
        
        // Fast forward past timelock
        vm.warp(block.timestamp + timelock + 1);
        
        // Now should be able to cancel
        vm.startPrank(alice);
        uint256 balanceBefore = alice.balance;
        resolver.cancelFusionOrder(orderHash);
        uint256 balanceAfter = alice.balance;
        assertGt(balanceAfter, balanceBefore);
        vm.stopPrank();
    }

    function testEscrowDstCloneDeployment() public {
        // Create order
        vm.startPrank(alice);
        uint256 amount = 1 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 timelock = 30 minutes;
        bytes32 secret = keccak256(abi.encodePacked("test-secret-6"));
        bytes32 hashlock = keccak256(abi.encodePacked(secret));
        
        MonadFusionPlusResolver.SwapParams memory params = MonadFusionPlusResolver.SwapParams({
            srcChainId: ETHEREUM_CHAIN_ID,
            dstChainId: MONAD_CHAIN_ID,
            srcToken: address(0),
            dstToken: address(0x123),
            amount: amount,
            deadline: deadline,
            hashlock: hashlock,
            timelock: timelock,
            recipient: bob
        });

        resolver.createFusionOrder{value: amount + 0.01 ether}(params);
        vm.stopPrank();
        
        bytes32 orderHash = resolver._computeOrderHash(params);
        
        // Fill order to trigger escrow deployment
        vm.startPrank(resolverAddress);
        vm.expectEmit(true, true, false, true);
        emit EscrowDeployed(orderHash, address(0), MONAD_CHAIN_ID, amount);
        
        resolver.fillFusionOrder(orderHash, charlie, amount, secret);
        vm.stopPrank();
        
        // Verify escrow info
        MonadFusionPlusResolver.EscrowInfo memory escrowInfo = resolver.getEscrowInfo(orderHash);
        assertTrue(escrowInfo.isDeployed);
        assertEq(escrowInfo.chainId, MONAD_CHAIN_ID);
        assertEq(escrowInfo.amount, amount);
    }

    function testBidirectionalSwapFlow() public {
        // Test Ethereum -> Monad
        vm.startPrank(alice);
        uint256 amount1 = 1 ether;
        uint256 deadline1 = block.timestamp + 1 hours;
        uint256 timelock1 = 30 minutes;
        bytes32 secret1 = keccak256(abi.encodePacked("secret-1"));
        bytes32 hashlock1 = keccak256(abi.encodePacked(secret1));
        
        MonadFusionPlusResolver.SwapParams memory params1 = MonadFusionPlusResolver.SwapParams({
            srcChainId: ETHEREUM_CHAIN_ID,
            dstChainId: MONAD_CHAIN_ID,
            srcToken: address(0),
            dstToken: address(0x123),
            amount: amount1,
            deadline: deadline1,
            hashlock: hashlock1,
            timelock: timelock1,
            recipient: bob
        });

        resolver.createFusionOrder{value: amount1 + 0.01 ether}(params1);
        vm.stopPrank();
        
        // Test Monad -> Ethereum
        vm.startPrank(bob);
        uint256 amount2 = 0.5 ether;
        uint256 deadline2 = block.timestamp + 1 hours;
        uint256 timelock2 = 30 minutes;
        bytes32 secret2 = keccak256(abi.encodePacked("secret-2"));
        bytes32 hashlock2 = keccak256(abi.encodePacked(secret2));
        
        MonadFusionPlusResolver.SwapParams memory params2 = MonadFusionPlusResolver.SwapParams({
            srcChainId: MONAD_CHAIN_ID,
            dstChainId: ETHEREUM_CHAIN_ID,
            srcToken: address(0x456),
            dstToken: address(0),
            amount: amount2,
            deadline: deadline2,
            hashlock: hashlock2,
            timelock: timelock2,
            recipient: alice
        });

        resolver.createFusionOrder{value: amount2 + 0.01 ether}(params2);
        vm.stopPrank();
        
        // Verify both orders exist
        bytes32 orderHash1 = resolver._computeOrderHash(params1);
        bytes32 orderHash2 = resolver._computeOrderHash(params2);
        
        MonadFusionPlusResolver.FusionOrder memory order1 = resolver.getFusionOrder(orderHash1);
        MonadFusionPlusResolver.FusionOrder memory order2 = resolver.getFusionOrder(orderHash2);
        
        assertTrue(order1.isActive);
        assertTrue(order2.isActive);
        assertEq(order1.srcChainId, ETHEREUM_CHAIN_ID);
        assertEq(order1.dstChainId, MONAD_CHAIN_ID);
        assertEq(order2.srcChainId, MONAD_CHAIN_ID);
        assertEq(order2.dstChainId, ETHEREUM_CHAIN_ID);
    }

    function testOnchainTokenTransferExecution() public {
        // Create order with ERC20 token
        vm.startPrank(alice);
        uint256 amount = 1 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 timelock = 30 minutes;
        bytes32 secret = keccak256(abi.encodePacked("test-secret-7"));
        bytes32 hashlock = keccak256(abi.encodePacked(secret));
        
        MonadFusionPlusResolver.SwapParams memory params = MonadFusionPlusResolver.SwapParams({
            srcChainId: ETHEREUM_CHAIN_ID,
            dstChainId: MONAD_CHAIN_ID,
            srcToken: address(0x789), // ERC20 token
            dstToken: address(0x123),
            amount: amount,
            deadline: deadline,
            hashlock: hashlock,
            timelock: timelock,
            recipient: bob
        });

        resolver.createFusionOrder{value: 0.01 ether}(params); // Only safety deposit
        vm.stopPrank();
        
        bytes32 orderHash = resolver._computeOrderHash(params);
        
        // Fill order (simulating onchain execution)
        vm.startPrank(resolverAddress);
        resolver.fillFusionOrder(orderHash, charlie, amount, secret);
        vm.stopPrank();
        
        // Verify order state
        MonadFusionPlusResolver.FusionOrder memory order = resolver.getFusionOrder(orderHash);
        assertTrue(order.isFilled);
        assertEq(order.filledAmount, amount);
        assertEq(order.remainingAmount, 0);
    }

    function testInvalidChainPair() public {
        vm.startPrank(alice);
        
        MonadFusionPlusResolver.SwapParams memory params = MonadFusionPlusResolver.SwapParams({
            srcChainId: ETHEREUM_CHAIN_ID,
            dstChainId: ETHEREUM_CHAIN_ID, // Same chain
            srcToken: address(0),
            dstToken: address(0x123),
            amount: 1 ether,
            deadline: block.timestamp + 1 hours,
            hashlock: keccak256(abi.encodePacked("secret")),
            timelock: 30 minutes,
            recipient: bob
        });

        vm.expectRevert("MonadFusionPlusResolver: Invalid chain pair");
        resolver.createFusionOrder{value: 1.01 ether}(params);
        
        vm.stopPrank();
    }

    function testInvalidSecret() public {
        // Create order
        vm.startPrank(alice);
        uint256 amount = 1 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 timelock = 30 minutes;
        bytes32 secret = keccak256(abi.encodePacked("correct-secret"));
        bytes32 hashlock = keccak256(abi.encodePacked(secret));
        
        MonadFusionPlusResolver.SwapParams memory params = MonadFusionPlusResolver.SwapParams({
            srcChainId: ETHEREUM_CHAIN_ID,
            dstChainId: MONAD_CHAIN_ID,
            srcToken: address(0),
            dstToken: address(0x123),
            amount: amount,
            deadline: deadline,
            hashlock: hashlock,
            timelock: timelock,
            recipient: bob
        });

        resolver.createFusionOrder{value: amount + 0.01 ether}(params);
        vm.stopPrank();
        
        bytes32 orderHash = resolver._computeOrderHash(params);
        
        // Try to fill with wrong secret
        vm.startPrank(resolverAddress);
        bytes32 wrongSecret = keccak256(abi.encodePacked("wrong-secret"));
        vm.expectRevert("MonadFusionPlusResolver: Invalid secret");
        resolver.fillFusionOrder(orderHash, charlie, amount, wrongSecret);
        vm.stopPrank();
    }

    function testOrderExpiration() public {
        vm.startPrank(alice);
        uint256 amount = 1 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 timelock = 30 minutes;
        bytes32 secret = keccak256(abi.encodePacked("test-secret-8"));
        bytes32 hashlock = keccak256(abi.encodePacked(secret));
        
        MonadFusionPlusResolver.SwapParams memory params = MonadFusionPlusResolver.SwapParams({
            srcChainId: ETHEREUM_CHAIN_ID,
            dstChainId: MONAD_CHAIN_ID,
            srcToken: address(0),
            dstToken: address(0x123),
            amount: amount,
            deadline: deadline,
            hashlock: hashlock,
            timelock: timelock,
            recipient: bob
        });

        resolver.createFusionOrder{value: amount + 0.01 ether}(params);
        vm.stopPrank();
        
        bytes32 orderHash = resolver._computeOrderHash(params);
        
        // Fast forward past deadline
        vm.warp(deadline + 1);
        
        // Try to fill expired order
        vm.startPrank(resolverAddress);
        vm.expectRevert("MonadFusionPlusResolver: Order expired");
        resolver.fillFusionOrder(orderHash, charlie, amount, secret);
        vm.stopPrank();
    }
} 