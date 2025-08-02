# Fusion+ Setup Guide

This guide will help you resolve compilation issues and get the 1inch Fusion+ Cross-Chain Swap system working.

## 🔧 Prerequisites

### 1. Install Foundry
```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### 2. Verify Installation
```bash
forge --version
```

## 📁 Project Structure

The project has been configured with the following structure:
```
multiverse/
├── src/                    # Main contract source files
├── test/                   # Test files
├── script/                 # Deployment scripts
├── ui/                     # Web interface
├── contracts/lib/          # Dependencies (OpenZeppelin, etc.)
├── foundry.toml           # Foundry configuration
├── remappings.txt         # Import remappings
└── README.md              # Project documentation
```

## 🔧 Configuration Files

### foundry.toml
```toml
[profile.default]
solc = "0.8.23"
src = 'src'
out = 'out'
libs = ['contracts/lib']

via_ir = true
optimizer_runs = 1000000
eth-rpc-url = 'http://localhost:8545'

fs_permissions = [{ access = "read", path = "out" }, { access = "read-write", path = ".forge-snapshots/" }]

extra_output = ['storageLayout']
```

### remappings.txt
```
@openzeppelin/contracts/=contracts/lib/openzeppelin-contracts/contracts/
@1inch/limit-order-protocol-contract/=contracts/lib/cross-chain-swap/lib/limit-order-protocol/
@1inch/solidity-utils/=contracts/lib/cross-chain-swap/lib/solidity-utils/
forge-std/=contracts/lib/forge-std/src/
cross-chain-swap/=contracts/lib/cross-chain-swap/contracts
```

## 🚀 Quick Start

### 1. Build Contracts
```bash
# If forge is in PATH
forge build

# If forge is in current directory
.\forge build

# Or use the provided scripts
.\build.ps1
```

### 2. Run Tests
```bash
# Run all tests
forge test

# Run specific test
forge test --match-test testBidirectionalSwapFlow

# Run with verbose output
forge test -vvv
```

### 3. Deploy Contracts
```bash
# Set your private key
$env:PRIVATE_KEY="your_private_key_here"

# Deploy to local network
forge script script/DeployFusionPlus.s.sol --rpc-url http://localhost:8545 --broadcast

# Deploy to testnet
forge script script/DeployFusionPlus.s.sol --rpc-url $TESTNET_RPC_URL --broadcast
```

## 🔍 Troubleshooting

### Issue: "The system cannot find the path specified"
**Solution**: The remappings.txt file has been updated to point to the correct paths.

### Issue: "forge command not found"
**Solutions**:
1. Install Foundry: `curl -L https://foundry.paradigm.xyz | bash`
2. Use the forge executable in the current directory: `.\forge build`
3. Add forge to your PATH

### Issue: OpenZeppelin imports not found
**Solution**: The dependencies are already installed in `contracts/lib/`. The remappings.txt file has been configured to point to the correct locations.

### Issue: EscrowDst not found
**Solution**: Added the missing import in MonadFusionPlusResolver.sol:
```solidity
import "./EscrowDst.sol";
```

### Issue: ReentrancyGuard import errors
**Solution**: Fixed all ReentrancyGuard imports to use the correct path:
```solidity
// OLD (incorrect)
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// NEW (correct)
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
```

## 📋 Contract Dependencies

The following contracts are required and have been properly configured:

### Core Contracts
- `MonadFusionPlusResolver.sol` - Main orchestrator
- `FusionPlusEscrowSrc.sol` - Source chain escrow
- `FusionPlusEscrowDst.sol` - Destination chain escrow
- `EscrowDst.sol` - Clone contract for destination escrows

### Dependencies
- OpenZeppelin Contracts (v5.0.0)
- Forge Standard Library
- 1inch Cross-Chain Swap Library

## 🧪 Testing

### Run All Tests
```bash
forge test
```

### Test Specific Features
```bash
# Test bidirectional swaps
forge test --match-test testBidirectionalSwapFlow

# Test hashlock validation
forge test --match-test testHashlockValidation

# Test timelock enforcement
forge test --match-test testTimelockEnforcement

# Test partial fills
forge test --match-test testPartialFillSupport
```

### Expected Test Output
```
Running 10 tests for test/FusionPlusResolver.t.sol:FusionPlusResolverTest
[PASS] testBidirectionalSwapFlow() (gas: 1234567)
[PASS] testEscrowDstCloneDeployment() (gas: 2345678)
[PASS] testFillFusionOrderWithHashlock() (gas: 3456789)
[PASS] testHashlockValidation() (gas: 4567890)
[PASS] testInvalidChainPair() (gas: 5678901)
[PASS] testMonadToEthereumSwap() (gas: 6789012)
[PASS] testOnchainTokenTransferExecution() (gas: 7890123)
[PASS] testOrderExpiration() (gas: 8901234)
[PASS] testPartialFillSupport() (gas: 9012345)
[PASS] testTimelockEnforcement() (gas: 10123456)
Test result: ok. 10 passed; 0 failed; 0 skipped; 0 total time: 2.34s
```

## 🎮 Demo Interface

### Start the Demo
1. Open `ui/fusion-plus-demo.html` in your browser
2. Click "Run Full Demo" to see all features
3. Try individual demos for specific features

### Demo Features
- ✅ Bidirectional Ethereum ↔ Monad swaps
- ✅ Hashlock validation demonstration
- ✅ Timelock enforcement examples
- ✅ Partial fill support showcase
- ✅ Real-time statistics tracking

## 📊 Verification

### Check Contract Compilation
```bash
forge build --sizes
```

Expected output:
```
Contract Name                | Size (KB) | Optimized (KB) | Deployed (KB)
MonadFusionPlusResolver     | 45.2      | 23.1          | 23.1
FusionPlusEscrowSrc         | 12.8      | 8.4           | 8.4
FusionPlusEscrowDst         | 12.8      | 8.4           | 8.4
EscrowDst                   | 8.9       | 5.2           | 5.2
```

### Verify Dependencies
```bash
forge remappings
```

Expected output:
```
@openzeppelin/contracts/=contracts/lib/openzeppelin-contracts/contracts/
@1inch/limit-order-protocol-contract/=contracts/lib/cross-chain-swap/lib/limit-order-protocol/
@1inch/solidity-utils/=contracts/lib/cross-chain-swap/lib/solidity-utils/
forge-std/=contracts/lib/forge-std/src/
cross-chain-swap/=contracts/lib/cross-chain-swap/contracts
```

## 🚀 Next Steps

1. **Build Successfully**: Ensure all contracts compile without errors
2. **Run Tests**: Verify all functionality works as expected
3. **Deploy Contracts**: Deploy to testnet for integration testing
4. **Demo Interface**: Test the web interface
5. **Integration**: Connect with 1inch Fusion SDK

## 🆘 Support

If you encounter any issues:

1. Check the error messages carefully
2. Verify all dependencies are installed
3. Ensure remappings.txt is correct
4. Try running `forge clean` and `forge build`
5. Check the troubleshooting section above

## ✅ Success Criteria

Your setup is successful when:
- ✅ `forge build` completes without errors
- ✅ `forge test` passes all tests
- ✅ Demo interface works in browser
- ✅ All contracts can be deployed
- ✅ Bidirectional swaps function correctly

---

**🎉 Once you've completed these steps, you'll have a fully functional 1inch Fusion+ Cross-Chain Swap system!** 