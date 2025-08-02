// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../src/CrossChainResolver.sol";
import "../src/Escrow.sol";

/**
 * @title CrossChainResolverTest
 * @dev Test suite for cross-chain resolver functionality
 */
contract CrossChainResolverTest is Test {
    CrossChainResolver public resolver;
    Escrow public escrow;
    
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    
    uint256 public constant MONAD_CHAIN_ID = 1337; // Replace with actual Monad chain ID
    uint256 public constant ETHEREUM_CHAIN_ID = 1;
    uint256 public constant BSC_CHAIN_ID = 56;
    
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

    event EscrowDeployed(
        bytes32 indexed orderHash,
        address indexed escrow,
        uint256 chainId,
        uint256 amount
    );

    function setUp() public {
        // Deploy contracts
        resolver = new CrossChainResolver();
        escrow = new Escrow();
        
        // Set up cross-references
        resolver.setAuthorizedResolver(address(escrow), true);
        escrow.setAuthorizedResolver(address(resolver), true);
        
        // Fund test accounts
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
    }

    function testCreateOrder() public {
        vm.startPrank(alice);
        
        uint256 amount = 1 ether;
        uint256 deadline = block.timestamp + 1 hours;
        address srcToken = address(0x123);
        address dstToken = address(0x456);
        
        vm.expectEmit(true, true, false, true);
        emit OrderCreated(
            bytes32(0), // We'll calculate this
            alice,
            ETHEREUM_CHAIN_ID,
            MONAD_CHAIN_ID,
            srcToken,
            dstToken,
            amount,
            deadline
        );
        
        resolver.createOrder{value: amount}(
            ETHEREUM_CHAIN_ID,
            MONAD_CHAIN_ID,
            srcToken,
            dstToken,
            amount,
            deadline
        );
        
        vm.stopPrank();
    }

    function testCreateOrderMonadToEthereum() public {
        vm.startPrank(bob);
        
        uint256 amount = 0.5 ether;
        uint256 deadline = block.timestamp + 1 hours;
        address srcToken = address(0x789);
        address dstToken = address(0xabc);
        
        resolver.createOrder{value: amount}(
            MONAD_CHAIN_ID,
            ETHEREUM_CHAIN_ID,
            srcToken,
            dstToken,
            amount,
            deadline
        );
        
        vm.stopPrank();
    }

    function testFillOrder() public {
        // Create order
        vm.startPrank(alice);
        uint256 amount = 1 ether;
        uint256 deadline = block.timestamp + 1 hours;
        
        resolver.createOrder{value: amount}(
            ETHEREUM_CHAIN_ID,
            MONAD_CHAIN_ID,
            address(0x123),
            address(0x456),
            amount,
            deadline
        );
        vm.stopPrank();
        
        // Get order hash
        bytes32 orderHash = keccak256(abi.encodePacked(
            alice,
            ETHEREUM_CHAIN_ID,
            MONAD_CHAIN_ID,
            address(0x123),
            address(0x456),
            amount,
            deadline,
            block.chainid
        ));
        
        // Fill order
        vm.startPrank(address(escrow));
        uint256 balanceBefore = charlie.balance;
        
        vm.expectEmit(true, true, false, true);
        emit OrderFilled(orderHash, charlie, amount, block.timestamp);
        
        resolver.fillOrder(orderHash, charlie, amount);
        
        uint256 balanceAfter = charlie.balance;
        assertEq(balanceAfter - balanceBefore, amount);
        vm.stopPrank();
    }

    function testCancelOrder() public {
        // Create order
        vm.startPrank(alice);
        uint256 amount = 1 ether;
        uint256 deadline = block.timestamp + 1 hours;
        
        resolver.createOrder{value: amount}(
            ETHEREUM_CHAIN_ID,
            MONAD_CHAIN_ID,
            address(0x123),
            address(0x456),
            amount,
            deadline
        );
        vm.stopPrank();
        
        // Get order hash
        bytes32 orderHash = keccak256(abi.encodePacked(
            alice,
            ETHEREUM_CHAIN_ID,
            MONAD_CHAIN_ID,
            address(0x123),
            address(0x456),
            amount,
            deadline,
            block.chainid
        ));
        
        // Cancel order
        vm.startPrank(alice);
        uint256 balanceBefore = alice.balance;
        
        resolver.cancelOrder(orderHash);
        
        uint256 balanceAfter = alice.balance;
        assertEq(balanceAfter - balanceBefore, amount);
        vm.stopPrank();
    }

    function testDeployEscrow() public {
        // Create order
        vm.startPrank(alice);
        uint256 amount = 1 ether;
        uint256 deadline = block.timestamp + 1 hours;
        
        resolver.createOrder{value: amount}(
            ETHEREUM_CHAIN_ID,
            MONAD_CHAIN_ID,
            address(0x123),
            address(0x456),
            amount,
            deadline
        );
        vm.stopPrank();
        
        // Get order hash
        bytes32 orderHash = keccak256(abi.encodePacked(
            alice,
            ETHEREUM_CHAIN_ID,
            MONAD_CHAIN_ID,
            address(0x123),
            address(0x456),
            amount,
            deadline,
            block.chainid
        ));
        
        // Deploy escrow
        vm.startPrank(address(escrow));
        address escrowAddress = address(0x999);
        
        vm.expectEmit(true, true, false, true);
        emit EscrowDeployed(orderHash, escrowAddress, MONAD_CHAIN_ID, amount);
        
        resolver.deployEscrow(orderHash, escrowAddress, MONAD_CHAIN_ID);
        vm.stopPrank();
    }

    function testCreateEscrow() public {
        vm.startPrank(alice);
        
        bytes32 orderHash = keccak256("test_order");
        address recipient = bob;
        bytes32 secretHash = keccak256(abi.encodePacked("secret"));
        uint256 deadline = block.timestamp + 1 hours;
        uint256 amount = 1 ether;
        
        escrow.createEscrow{value: amount}(
            orderHash,
            recipient,
            secretHash,
            deadline
        );
        
        vm.stopPrank();
    }

    function testWithdrawEscrow() public {
        // Create escrow
        vm.startPrank(alice);
        bytes32 orderHash = keccak256("test_order");
        address recipient = bob;
        bytes32 secret = keccak256("secret");
        bytes32 secretHash = keccak256(abi.encodePacked(secret));
        uint256 deadline = block.timestamp + 1 hours;
        uint256 amount = 1 ether;
        
        escrow.createEscrow{value: amount}(
            orderHash,
            recipient,
            secretHash,
            deadline
        );
        vm.stopPrank();
        
        // Withdraw
        vm.startPrank(bob);
        uint256 balanceBefore = bob.balance;
        
        escrow.withdraw(orderHash, secret);
        
        uint256 balanceAfter = bob.balance;
        assertEq(balanceAfter - balanceBefore, amount);
        vm.stopPrank();
    }

    function testCancelEscrow() public {
        // Create escrow
        vm.startPrank(alice);
        bytes32 orderHash = keccak256("test_order");
        address recipient = bob;
        bytes32 secretHash = keccak256(abi.encodePacked("secret"));
        uint256 deadline = block.timestamp + 1 hours;
        uint256 amount = 1 ether;
        
        escrow.createEscrow{value: amount}(
            orderHash,
            recipient,
            secretHash,
            deadline
        );
        vm.stopPrank();
        
        // Cancel escrow
        vm.startPrank(alice);
        uint256 balanceBefore = alice.balance;
        
        escrow.cancelEscrow(orderHash);
        
        uint256 balanceAfter = alice.balance;
        assertEq(balanceAfter - balanceBefore, amount);
        vm.stopPrank();
    }

    function testChainSupport() public {
        assertTrue(resolver.isChainSupported(ETHEREUM_CHAIN_ID));
        assertTrue(resolver.isChainSupported(MONAD_CHAIN_ID));
        assertTrue(resolver.isChainSupported(BSC_CHAIN_ID));
        assertFalse(resolver.isChainSupported(999)); // Unsupported chain
    }

    function testUnauthorizedAccess() public {
        vm.startPrank(charlie);
        
        // Try to fill order without authorization
        vm.expectRevert("CrossChainResolver: Unauthorized resolver");
        resolver.fillOrder(bytes32(0), charlie, 1 ether);
        
        vm.stopPrank();
    }

    function testOrderValidation() public {
        vm.startPrank(alice);
        
        // Try to create order with same source and destination chain
        vm.expectRevert("CrossChainResolver: Same chain not allowed");
        resolver.createOrder{value: 1 ether}(
            ETHEREUM_CHAIN_ID,
            ETHEREUM_CHAIN_ID,
            address(0x123),
            address(0x456),
            1 ether,
            block.timestamp + 1 hours
        );
        
        vm.stopPrank();
    }

    function testAmountValidation() public {
        vm.startPrank(alice);
        
        // Try to create order with amount too low
        vm.expectRevert("CrossChainResolver: Amount too low");
        resolver.createOrder{value: 0.0001 ether}(
            ETHEREUM_CHAIN_ID,
            MONAD_CHAIN_ID,
            address(0x123),
            address(0x456),
            0.0001 ether,
            block.timestamp + 1 hours
        );
        
        vm.stopPrank();
    }

    function testDeadlineValidation() public {
        vm.startPrank(alice);
        
        // Try to create order with past deadline
        vm.expectRevert("CrossChainResolver: Invalid deadline");
        resolver.createOrder{value: 1 ether}(
            ETHEREUM_CHAIN_ID,
            MONAD_CHAIN_ID,
            address(0x123),
            address(0x456),
            1 ether,
            block.timestamp - 1 hours
        );
        
        vm.stopPrank();
    }
} 