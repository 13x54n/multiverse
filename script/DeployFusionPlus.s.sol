// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../src/MonadFusionPlusResolver.sol";
import "../src/FusionPlusEscrowSrc.sol";
import "../src/FusionPlusEscrowDst.sol";

/**
 * @title DeployFusionPlusScript
 * @dev Deployment script for 1inch Fusion+ cross-chain swap system
 */
contract DeployFusionPlusScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying 1inch Fusion+ Cross-Chain Swap System...");
        console.log("Deployer:", deployer);

        // Deploy Fusion+ Resolver
        console.log("\nDeploying MonadFusionPlusResolver...");
        MonadFusionPlusResolver resolver = new MonadFusionPlusResolver();
        console.log("MonadFusionPlusResolver deployed at:", address(resolver));

        // Deploy Source Escrow
        console.log("\nDeploying FusionPlusEscrowSrc...");
        FusionPlusEscrowSrc escrowSrc = new FusionPlusEscrowSrc();
        console.log("FusionPlusEscrowSrc deployed at:", address(escrowSrc));

        // Deploy Destination Escrow
        console.log("\nDeploying FusionPlusEscrowDst...");
        FusionPlusEscrowDst escrowDst = new FusionPlusEscrowDst();
        console.log("FusionPlusEscrowDst deployed at:", address(escrowDst));

        // Set up cross-references
        console.log("\nSetting up cross-references...");
        
        // Set authorized resolvers
        resolver.setAuthorizedResolver(address(escrowSrc), true);
        resolver.setAuthorizedResolver(address(escrowDst), true);
        escrowSrc.setAuthorizedResolver(address(resolver), true);
        escrowDst.setAuthorizedResolver(address(resolver), true);

        console.log("Cross-references configured successfully");

        // Update parameters for optimal settings
        console.log("\nConfiguring parameters...");
        
        // Resolver parameters
        resolver.updateOrderParameters(
            0.001 ether,  // minOrderAmount
            1000 ether,   // maxOrderAmount
            1 hours       // orderTimeout
        );
        
        resolver.updateFees(
            0.01 ether,   // safetyDeposit
            0.001 ether   // resolverFee
        );

        // Escrow parameters
        escrowSrc.updateParameters(
            0.001 ether,  // minDepositAmount
            1000 ether,   // maxDepositAmount
            1 hours       // defaultTimelock
        );

        escrowDst.updateParameters(
            0.001 ether,  // minDepositAmount
            1000 ether,   // maxDepositAmount
            1 hours       // defaultTimelock
        );

        console.log("Parameters configured successfully");

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("Chain ID:", block.chainid);
        console.log("MonadFusionPlusResolver:", address(resolver));
        console.log("FusionPlusEscrowSrc:", address(escrowSrc));
        console.log("FusionPlusEscrowDst:", address(escrowDst));
        console.log("Deployer:", deployer);
        console.log("==========================");

        // Save deployment addresses
        string memory deploymentInfo = string(abi.encodePacked(
            "Deployment Info:\n",
            "Chain ID: ", vm.toString(block.chainid), "\n",
            "MonadFusionPlusResolver: ", vm.toString(address(resolver)), "\n",
            "FusionPlusEscrowSrc: ", vm.toString(address(escrowSrc)), "\n",
            "FusionPlusEscrowDst: ", vm.toString(address(escrowDst)), "\n",
            "Deployer: ", vm.toString(deployer), "\n"
        ));

        vm.writeFile("deployment-info.txt", deploymentInfo);
        console.log("\nDeployment info saved to deployment-info.txt");
    }
} 