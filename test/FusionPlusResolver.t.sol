// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../src/MonadFusionPlusResolver.sol";
import "../src/FusionPlusEscrowSrc.sol";
import "../src/FusionPlusEscrowDst.sol";

/**
 * @title FusionPlusResolverTest
 * @dev Comprehensive test suite for 1inch Fusion+ cross-chain swap system
 */
contract FusionPlusResolverTest is Test {
    MonadFusionPlusResolver public resolver;
    FusionPlusEscrowSrc public escrowSrc;
    FusionPlusEscrowDst public escrowDst;
    
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    address public resolverAddress = address(0x4);
    
    uint256 public constant ETHEREUM_CHAIN_ID = 1;
    uint256 public constant MONAD_CHAIN_ID = 1337;
    
    // Test tokens
    address public constant ETH_TOKEN = address(0);
    address public constant USDC_ETH = address(0xA0b86a33E6441b8C4C3B0C8C3B0C8C3B0C8C3B0C);
    address public constant USDC_MONAD = address(0xB0b86a33E6441b8C4C3B0C8C3B0C8C3B0C8C3B0C);
    
    bytes32 public testHashlock;
    bytes32 public testSecret;

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
        // Generate test secret and hashlock
        testSecret = keccak256(abi.encodePacked("test-secret", block.timestamp));
        testHashlock = keccak256(abi.encodePacked(testSecret));
        
        // Deploy contracts
        resolver = new MonadFusionPlusResolver();
        escrowSrc = new FusionPlusEscrowSrc();
        escrowDst = new FusionPlusEscrowDst();
        
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
        
        vm.expectEmit(true, true, false, true);
        emit FusionOrderCreated(
            bytes32(0), // We'll calculate this
            alice,
            ETHEREUM_CHAIN_ID,
            MONAD_CHAIN_ID,
            ETH_TOKEN,
            USDC_MONAD,
            amount,
            deadline,
            testHashlock,
            timelock
        );
        
        resolver.createFusionOrder{value: amount + 0.01 ether}(MonadFusionPlusResolver.SwapParams({
            srcChainId: ETHEREUM_CHAIN_ID,
            dstChainId: MONAD_CHAIN_ID,
            srcToken: ETH_TOKEN,
            dstToken: USDC_MONAD,
            amount: amount,
            deadline: deadline,
            hashlock: testHashlock,
            timelock: timelock,
            recipient: bob
        }));
        
        vm.stopPrank();
    }

    function testCreateFusionOrderMonadToEthereum() public {
        vm.startPrank(bob);
        
        uint256 amount = 0.5 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 timelock = 30 minutes;
        
        vm.expectEmit(true, true, false, true);
        emit FusionOrderCreated(
            bytes32(0), // We'll calculate this
            bob,
            MONAD_CHAIN_ID,
            ETHEREUM_CHAIN_ID,
            USDC_MONAD,
            ETH_TOKEN,
            amount,
            deadline,
            testHashlock,
            timelock
        );
        
        resolver.createFusionOrder{value: amount + 0.01 ether}(MonadFusionPlusResolver.SwapParams({
            srcChainId: MONAD_CHAIN_ID,
            dstChainId: ETHEREUM_CHAIN_ID,
            srcToken: USDC_MONAD,
            dstToken: ETH_TOKEN,
            amount: amount,
            deadline: deadline,
            hashlock: testHashlock,
            timelock: timelock,
            recipient: alice
        }));
        
        vm.stopPrank();
    }

    function testFillFusionOrder() public {
        // Create order
        vm.startPrank(alice);
        uint256 amount = 1 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 timelock = 30 minutes;
        
        resolver.createFusionOrder{value: amount + 0.01 ether}(MonadFusionPlusResolver.SwapParams({
            srcChainId: ETHEREUM_CHAIN_ID,
            dstChainId: MONAD_CHAIN_ID,
            srcToken: ETH_TOKEN,
            dstToken: USDC_MONAD,
            amount: amount,
            deadline: deadline,
            hashlock: testHashlock,
            timelock: timelock,
            recipient: bob
        }));
        vm.stopPrank();
        
        // Get order hash
        bytes32 orderHash = _computeOrderHash(ETHEREUM_CHAIN_ID, MONAD_CHAIN_ID, ETH_TOKEN, USDC_MONAD, amount, deadline, testHashlock, timelock, alice);
        
        // Fill order
        vm.startPrank(resolverAddress);
        uint256 balanceBefore = bob.balance;
        
        vm.expectEmit(true, true, false, true);
        emit FusionOrderFilled(orderHash, bob, amount, testSecret, block.timestamp);
        
        resolver.fillFusionOrder(orderHash, bob, amount, testSecret);
        
        uint256 balanceAfter = bob.balance;
        assertEq(balanceAfter - balanceBefore, amount, "Taker should receive the correct amount");
        vm.stopPrank();
    }

    function testPartialFill() public {
        // Create order
        vm.startPrank(alice);
        uint256 amount = 2 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 timelock = 30 minutes;
        
        resolver.createFusionOrder{value: amount + 0.01 ether}(MonadFusionPlusResolver.SwapParams({
            srcChainId: ETHEREUM_CHAIN_ID,
            dstChainId: MONAD_CHAIN_ID,
            srcToken: ETH_TOKEN,
            dstToken: USDC_MONAD,
            amount: amount,
            deadline: deadline,
            hashlock: testHashlock,
            timelock: timelock,
            recipient: bob
        }));
        vm.stopPrank();
        
        // Get order hash
        bytes32 orderHash = _computeOrderHash(ETHEREUM_CHAIN_ID, MONAD_CHAIN_ID, ETH_TOKEN, USDC_MONAD, amount, deadline, testHashlock, timelock, alice);
        
        // First partial fill
        vm.startPrank(resolverAddress);
        uint256 partialAmount1 = 0.5 ether;
        resolver.fillFusionOrder(orderHash, bob, partialAmount1, testSecret);
        
        MonadFusionPlusResolver.FusionOrder memory order = resolver.getFusionOrder(orderHash);
        assertEq(order.filledAmount, partialAmount1, "Filled amount should be correct");
        assertEq(order.remainingAmount, amount - partialAmount1, "Remaining amount should be correct");
        assertTrue(order.isActive, "Order should still be active");
        
        // Second partial fill
        uint256 partialAmount2 = 0.3 ether;
        resolver.fillFusionOrder(orderHash, charlie, partialAmount2, testSecret);
        
        order = resolver.getFusionOrder(orderHash);
        assertEq(order.filledAmount, partialAmount1 + partialAmount2, "Total filled amount should be correct");
        assertEq(order.remainingAmount, amount - partialAmount1 - partialAmount2, "Remaining amount should be correct");
        
        // Final fill
        uint256 finalAmount = amount - partialAmount1 - partialAmount2;
        resolver.fillFusionOrder(orderHash, alice, finalAmount, testSecret);
        
        order = resolver.getFusionOrder(orderHash);
        assertEq(order.filledAmount, amount, "Total filled amount should equal original amount");
        assertEq(order.remainingAmount, 0, "Remaining amount should be zero");
        assertFalse(order.isActive, "Order should be inactive");
        assertTrue(order.isFilled, "Order should be marked as filled");
        vm.stopPrank();
    }

    function testCancelFusionOrder() public {
        // Create order
        vm.startPrank(alice);
        uint256 amount = 1 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 timelock = 30 minutes;
        
        resolver.createFusionOrder{value: amount + 0.01 ether}(MonadFusionPlusResolver.SwapParams({
            srcChainId: ETHEREUM_CHAIN_ID,
            dstChainId: MONAD_CHAIN_ID,
            srcToken: ETH_TOKEN,
            dstToken: USDC_MONAD,
            amount: amount,
            deadline: deadline,
            hashlock: testHashlock,
            timelock: timelock,
            recipient: bob
        }));
        vm.stopPrank();
        
        // Get order hash
        bytes32 orderHash = _computeOrderHash(ETHEREUM_CHAIN_ID, MONAD_CHAIN_ID, ETH_TOKEN, USDC_MONAD, amount, deadline, testHashlock, timelock, alice);
        
        // Cancel order
        vm.startPrank(alice);
        uint256 balanceBefore = alice.balance;
        
        resolver.cancelFusionOrder(orderHash);
        
        uint256 balanceAfter = alice.balance;
        assertEq(balanceAfter - balanceBefore, amount + 0.01 ether, "Maker should receive refund");
        
        MonadFusionPlusResolver.FusionOrder memory order = resolver.getFusionOrder(orderHash);
        assertFalse(order.isActive, "Order should be inactive");
        assertTrue(order.isCancelled, "Order should be marked as cancelled");
        vm.stopPrank();
    }

    function testWithdrawFromEscrow() public {
        // Create and fill order to deploy escrow
        vm.startPrank(alice);
        uint256 amount = 1 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 timelock = 30 minutes;
        
        resolver.createFusionOrder{value: amount + 0.01 ether}(MonadFusionPlusResolver.SwapParams({
            srcChainId: ETHEREUM_CHAIN_ID,
            dstChainId: MONAD_CHAIN_ID,
            srcToken: ETH_TOKEN,
            dstToken: USDC_MONAD,
            amount: amount,
            deadline: deadline,
            hashlock: testHashlock,
            timelock: timelock,
            recipient: bob
        }));
        vm.stopPrank();
        
        bytes32 orderHash = _computeOrderHash(ETHEREUM_CHAIN_ID, MONAD_CHAIN_ID, ETH_TOKEN, USDC_MONAD, amount, deadline, testHashlock, timelock, alice);
        
        // Fill order to deploy escrow
        vm.startPrank(resolverAddress);
        resolver.fillFusionOrder(orderHash, bob, amount, testSecret);
        vm.stopPrank();
        
        // Withdraw from escrow
        vm.startPrank(bob);
        uint256 balanceBefore = bob.balance;
        
        resolver.withdrawFromEscrow(orderHash, testSecret);
        
        uint256 balanceAfter = bob.balance;
        assertGt(balanceAfter, balanceBefore, "Recipient should receive tokens from escrow");
        vm.stopPrank();
    }

    function testBidirectionalSwaps() public {
        // Test Ethereum to Monad
        vm.startPrank(alice);
        uint256 amount1 = 1 ether;
        resolver.createFusionOrder{value: amount1 + 0.01 ether}(MonadFusionPlusResolver.SwapParams({
            srcChainId: ETHEREUM_CHAIN_ID,
            dstChainId: MONAD_CHAIN_ID,
            srcToken: ETH_TOKEN,
            dstToken: USDC_MONAD,
            amount: amount1,
            deadline: block.timestamp + 1 hours,
            hashlock: testHashlock,
            timelock: 30 minutes,
            recipient: bob
        }));
        vm.stopPrank();
        
        // Test Monad to Ethereum
        vm.startPrank(bob);
        uint256 amount2 = 0.5 ether;
        resolver.createFusionOrder{value: amount2 + 0.01 ether}(MonadFusionPlusResolver.SwapParams({
            srcChainId: MONAD_CHAIN_ID,
            dstChainId: ETHEREUM_CHAIN_ID,
            srcToken: USDC_MONAD,
            dstToken: ETH_TOKEN,
            amount: amount2,
            deadline: block.timestamp + 1 hours,
            hashlock: testHashlock,
            timelock: 30 minutes,
            recipient: alice
        }));
        vm.stopPrank();
        
        // Verify both orders exist
        bytes32 orderHash1 = _computeOrderHash(ETHEREUM_CHAIN_ID, MONAD_CHAIN_ID, ETH_TOKEN, USDC_MONAD, amount1, block.timestamp + 1 hours, testHashlock, 30 minutes, alice);
        bytes32 orderHash2 = _computeOrderHash(MONAD_CHAIN_ID, ETHEREUM_CHAIN_ID, USDC_MONAD, ETH_TOKEN, amount2, block.timestamp + 1 hours, testHashlock, 30 minutes, bob);
        
        assertTrue(resolver.isOrderActive(orderHash1), "First order should be active");
        assertTrue(resolver.isOrderActive(orderHash2), "Second order should be active");
    }

    function testHashlockValidation() public {
        vm.startPrank(alice);
        uint256 amount = 1 ether;
        
        resolver.createFusionOrder{value: amount + 0.01 ether}(MonadFusionPlusResolver.SwapParams({
            srcChainId: ETHEREUM_CHAIN_ID,
            dstChainId: MONAD_CHAIN_ID,
            srcToken: ETH_TOKEN,
            dstToken: USDC_MONAD,
            amount: amount,
            deadline: block.timestamp + 1 hours,
            hashlock: testHashlock,
            timelock: 30 minutes,
            recipient: bob
        }));
        vm.stopPrank();
        
        bytes32 orderHash = _computeOrderHash(ETHEREUM_CHAIN_ID, MONAD_CHAIN_ID, ETH_TOKEN, USDC_MONAD, amount, block.timestamp + 1 hours, testHashlock, 30 minutes, alice);
        
        // Try to fill with wrong secret
        vm.startPrank(resolverAddress);
        bytes32 wrongSecret = keccak256(abi.encodePacked("wrong-secret"));
        
        vm.expectRevert("MonadFusionPlusResolver: Invalid secret");
        resolver.fillFusionOrder(orderHash, bob, amount, wrongSecret);
        vm.stopPrank();
    }

    function testTimelockFunctionality() public {
        vm.startPrank(alice);
        uint256 amount = 1 ether;
        uint256 timelock = 30 minutes;
        
        resolver.createFusionOrder{value: amount + 0.01 ether}(MonadFusionPlusResolver.SwapParams({
            srcChainId: ETHEREUM_CHAIN_ID,
            dstChainId: MONAD_CHAIN_ID,
            srcToken: ETH_TOKEN,
            dstToken: USDC_MONAD,
            amount: amount,
            deadline: block.timestamp + 1 hours,
            hashlock: testHashlock,
            timelock: timelock,
            recipient: bob
        }));
        vm.stopPrank();
        
        bytes32 orderHash = _computeOrderHash(ETHEREUM_CHAIN_ID, MONAD_CHAIN_ID, ETH_TOKEN, USDC_MONAD, amount, block.timestamp + 1 hours, testHashlock, timelock, alice);
        
        // Try to cancel before timelock expires
        vm.startPrank(alice);
        vm.expectRevert("MonadFusionPlusResolver: Cannot cancel order");
        resolver.cancelFusionOrder(orderHash);
        vm.stopPrank();
        
        // Fast forward time
        vm.warp(block.timestamp + timelock + 1);
        
        // Now should be able to cancel
        vm.startPrank(alice);
        resolver.cancelFusionOrder(orderHash);
        vm.stopPrank();
    }

    function testAccessControl() public {
        vm.startPrank(alice);
        uint256 amount = 1 ether;
        
        resolver.createFusionOrder{value: amount + 0.01 ether}(MonadFusionPlusResolver.SwapParams({
            srcChainId: ETHEREUM_CHAIN_ID,
            dstChainId: MONAD_CHAIN_ID,
            srcToken: ETH_TOKEN,
            dstToken: USDC_MONAD,
            amount: amount,
            deadline: block.timestamp + 1 hours,
            hashlock: testHashlock,
            timelock: 30 minutes,
            recipient: bob
        }));
        vm.stopPrank();
        
        bytes32 orderHash = _computeOrderHash(ETHEREUM_CHAIN_ID, MONAD_CHAIN_ID, ETH_TOKEN, USDC_MONAD, amount, block.timestamp + 1 hours, testHashlock, 30 minutes, alice);
        
        // Try to fill with unauthorized address
        vm.startPrank(charlie);
        vm.expectRevert("MonadFusionPlusResolver: Unauthorized resolver");
        resolver.fillFusionOrder(orderHash, bob, amount, testSecret);
        vm.stopPrank();
    }

    // Helper function to compute order hash
    function _computeOrderHash(
        uint256 srcChainId,
        uint256 dstChainId,
        address srcToken,
        address dstToken,
        uint256 amount,
        uint256 deadline,
        bytes32 hashlock,
        uint256 timelock,
        address maker
    ) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(
            srcChainId,
            dstChainId,
            srcToken,
            dstToken,
            amount,
            deadline,
            hashlock,
            timelock,
            maker,
            block.chainid
        ));
    }
} 