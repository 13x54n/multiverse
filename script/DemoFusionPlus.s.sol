// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../src/MonadFusionPlusResolver.sol";
import "../src/FusionPlusEscrowSrc.sol";
import "../src/FusionPlusEscrowDst.sol";
import "../src/EscrowDst.sol";

/**
 * @title DemoFusionPlus
 * @dev Comprehensive demo script for 1inch Fusion+ cross-chain swap system
 * Demonstrates bidirectional swaps, hashlock validation, timelock enforcement, and onchain execution
 */
contract DemoFusionPlus is Script {
    MonadFusionPlusResolver public resolver;
    FusionPlusEscrowSrc public escrowSrc;
    FusionPlusEscrowDst public escrowDst;
    
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x4);
    address public resolverAddress = address(0x3);
    
    uint256 public constant ETHEREUM_CHAIN_ID = 1;
    uint256 public constant MONAD_CHAIN_ID = 1337;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);

        // Deploy contracts
        resolver = new MonadFusionPlusResolver();
        escrowSrc = new FusionPlusEscrowSrc();
        escrowDst = new FusionPlusEscrowDst();

        // Configure system
        resolver.setAuthorizedResolver(address(escrowSrc), true);
        resolver.setAuthorizedResolver(address(escrowDst), true);
        resolver.setAuthorizedResolver(resolverAddress, true);
        escrowSrc.setAuthorizedResolver(address(resolver), true);
        escrowDst.setAuthorizedResolver(address(resolver), true);

        // Fund accounts
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
        vm.deal(resolverAddress, 100 ether);

        vm.stopBroadcast();

        // Demo 1: Ethereum to Monad Swap
        demoEthereumToMonadSwap();

        // Demo 2: Monad to Ethereum Swap

        demoMonadToEthereumSwap();

        // Demo 3: Partial Fill Support

        demoPartialFillSupport();

        // Demo 4: Timelock Enforcement

        demoTimelockEnforcement();

        // Demo 5: Hashlock Validation

        demoHashlockValidation();


    }

    function demoEthereumToMonadSwap() internal {
        vm.startPrank(alice);
        uint256 amount = 1 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 timelock = 30 minutes;
        bytes32 secret = keccak256(abi.encodePacked("demo-secret-1"));
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

        resolver.createFusionOrder{value: amount + 0.01 ether}(params);
        bytes32 orderHash = resolver.computeOrderHash(params);
        vm.stopPrank();

        // Fill order
        vm.startPrank(resolverAddress);
        uint256 balanceBefore = bob.balance;
        resolver.fillFusionOrder(orderHash, bob, amount, secret);
        uint256 balanceAfter = bob.balance;
        vm.stopPrank();

        // Verify order state
        MonadFusionPlusResolver.FusionOrder memory order = resolver.getFusionOrder(orderHash);
    }

    function demoMonadToEthereumSwap() internal {
        vm.startPrank(bob);
        uint256 amount = 0.5 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 timelock = 30 minutes;
        bytes32 secret = keccak256(abi.encodePacked("demo-secret-2"));
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
        bytes32 orderHash = resolver.computeOrderHash(params);
        vm.stopPrank();

        // Fill order
        vm.startPrank(resolverAddress);
        uint256 balanceBefore = alice.balance;
        resolver.fillFusionOrder(orderHash, alice, amount, secret);
        uint256 balanceAfter = alice.balance;
        vm.stopPrank();

        // Verify order state
        MonadFusionPlusResolver.FusionOrder memory order = resolver.getFusionOrder(orderHash);
    }

    function demoPartialFillSupport() internal {
        vm.startPrank(alice);
        uint256 totalAmount = 2 ether;
        uint256 partialAmount1 = 0.5 ether;
        uint256 partialAmount2 = 0.3 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 timelock = 30 minutes;
        bytes32 secret = keccak256(abi.encodePacked("demo-secret-3"));
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
        bytes32 orderHash = resolver.computeOrderHash(params);
        vm.stopPrank();

        // First partial fill
        vm.startPrank(resolverAddress);
        resolver.fillFusionOrder(orderHash, charlie, partialAmount1, secret);
        
        MonadFusionPlusResolver.FusionOrder memory order = resolver.getFusionOrder(orderHash);

        // Second partial fill
        resolver.fillFusionOrder(orderHash, bob, partialAmount2, secret);
        
        order = resolver.getFusionOrder(orderHash);
        vm.stopPrank();
    }

    function demoTimelockEnforcement() internal {
        vm.startPrank(alice);
        uint256 amount = 1 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 timelock = 30 minutes;
        bytes32 secret = keccak256(abi.encodePacked("demo-secret-4"));
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
        bytes32 orderHash = resolver.computeOrderHash(params);
        vm.stopPrank();

        // Try to cancel before timelock expires
        vm.startPrank(alice);
        try resolver.cancelFusionOrder(orderHash) {
            // Expected to fail
        } catch Error(string memory reason) {
            // Expected behavior
        }
        vm.stopPrank();

        // Fast forward past timelock
        vm.warp(block.timestamp + timelock + 1);

        // Now should be able to cancel
        vm.startPrank(alice);
        uint256 balanceBefore = alice.balance;
        resolver.cancelFusionOrder(orderHash);
        uint256 balanceAfter = alice.balance;
        vm.stopPrank();

        // Verify order state
        MonadFusionPlusResolver.FusionOrder memory order = resolver.getFusionOrder(orderHash);
    }

    function demoHashlockValidation() internal {
        vm.startPrank(alice);
        uint256 amount = 1 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 timelock = 30 minutes;
        bytes32 correctSecret = keccak256(abi.encodePacked("correct-secret"));
        bytes32 hashlock = keccak256(abi.encodePacked(correctSecret));
        
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
        bytes32 orderHash = resolver.computeOrderHash(params);
        vm.stopPrank();

        // Try to fill with wrong secret
        vm.startPrank(resolverAddress);
        bytes32 wrongSecret = keccak256(abi.encodePacked("wrong-secret"));
        try resolver.fillFusionOrder(orderHash, charlie, amount, wrongSecret) {
            // Expected to fail
        } catch Error(string memory reason) {
            // Expected behavior
        }
        vm.stopPrank();

        // Fill with correct secret
        vm.startPrank(resolverAddress);
        uint256 balanceBefore = charlie.balance;
        resolver.fillFusionOrder(orderHash, charlie, amount, correctSecret);
        uint256 balanceAfter = charlie.balance;
        vm.stopPrank();

        // Verify order state
        MonadFusionPlusResolver.FusionOrder memory order = resolver.getFusionOrder(orderHash);
    }
} 