// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../src/CrossChainResolver.sol";
import "../src/Escrow.sol";

/**
 * @title Deploy
 * @dev Deployment script for cross-chain resolver contracts
 */
contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);

        // Deploy CrossChainResolver
        CrossChainResolver resolver = new CrossChainResolver();
        console.log("CrossChainResolver deployed at:", address(resolver));

        // Deploy Escrow
        Escrow escrow = new Escrow();
        console.log("Escrow deployed at:", address(escrow));

        // Set up cross-references
        resolver.setAuthorizedResolver(address(escrow), true);
        escrow.setAuthorizedResolver(address(resolver), true);

        // Configure Monad chain support
        // Note: Replace with actual Monad chain ID when available
        uint256 monadChainId = 1337; // Placeholder - replace with actual Monad chain ID
        resolver.setSupportedChain(monadChainId, true);
        
        console.log("Monad chain (ID:", monadChainId, ") support enabled");

        vm.stopBroadcast();

        console.log("Deployment completed successfully!");
        console.log("CrossChainResolver:", address(resolver));
        console.log("Escrow:", address(escrow));
    }
} 