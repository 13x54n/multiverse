// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../src/MonadFusionPlusResolver.sol";
import "../src/FusionPlusEscrowSrc.sol";
import "../src/FusionPlusEscrowDst.sol";
import "../src/EscrowDst.sol";

/**
 * @title DeployFusionPlus
 * @dev Deployment script for 1inch Fusion+ cross-chain swap system
 * Deploys all contracts and configures cross-chain infrastructure
 */
contract DeployFusionPlus is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);

        // Deploy MonadFusionPlusResolver
        MonadFusionPlusResolver resolver = new MonadFusionPlusResolver();

        // Deploy FusionPlusEscrowSrc (Source chain escrow)
        FusionPlusEscrowSrc escrowSrc = new FusionPlusEscrowSrc();

        // Deploy FusionPlusEscrowDst (Destination chain escrow)
        FusionPlusEscrowDst escrowDst = new FusionPlusEscrowDst();

        // Deploy EscrowDst implementation (for clones)
        EscrowDst escrowDstImpl = new EscrowDst(
            address(0), // token placeholder
            0,          // amount placeholder
            address(0), // recipient placeholder
            bytes32(0), // hashlock placeholder
            0           // timelock placeholder
        );

        // Configure cross-references
        
        // Set authorized resolvers
        resolver.setAuthorizedResolver(address(escrowSrc), true);
        resolver.setAuthorizedResolver(address(escrowDst), true);
        resolver.setAuthorizedResolver(vm.addr(deployerPrivateKey), true);
        
        escrowSrc.setAuthorizedResolver(address(resolver), true);
        escrowDst.setAuthorizedResolver(address(resolver), true);

        // Configure chain support
        uint256 ethereumChainId = 1;
        uint256 monadChainId = 1337; // Replace with actual Monad chain ID
        
        resolver.setSupportedChain(ethereumChainId, true);
        resolver.setSupportedChain(monadChainId, true);

        // Configure order parameters
        resolver.updateOrderParameters(
            0.001 ether,  // minOrderAmount
            1000 ether,   // maxOrderAmount
            1 hours       // orderTimeout
        );

        // Configure fees
        resolver.updateFees(
            0.01 ether,   // safetyDeposit
            0.001 ether   // resolverFee
        );

        // Configure escrow parameters
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

        vm.stopBroadcast();
    }
} 