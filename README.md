# Monad Cross-Chain Resolver

A cross-chain resolver implementation that supports Monad chain and other EVM chains for decentralized cross-chain trading and escrow management.

## Overview

This project implements a cross-chain resolver system that enables:
- Cross-chain order creation and management
- Secure escrow functionality
- Support for Monad chain and other EVM chains
- Authorized resolver system for order execution

## Features

### Cross-Chain Resolver
- **Order Management**: Create, fill, and cancel cross-chain orders
- **Chain Support**: Native support for Monad, Ethereum, BSC, and Polygon
- **Security**: Reentrancy protection and access control
- **Flexible Parameters**: Configurable order amounts and timeouts

### Escrow System
- **Secure Deposits**: Hash-locked escrow deposits
- **Secret-based Withdrawals**: Cryptographic secret for fund release
- **Cancellation Support**: Timeout-based cancellation
- **Force Withdrawal**: Authorized resolver override capabilities

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Source Chain  │    │  Cross-Chain    │    │ Destination     │
│                 │    │   Resolver      │    │     Chain       │
│ ┌─────────────┐ │    │ ┌─────────────┐ │    │ ┌─────────────┐ │
│ │   Order     │ │    │ │   Order     │ │    │ │   Escrow    │ │
│ │  Creation   │ │───▶│ │ Management  │ │───▶│ │ Deployment  │ │
│ └─────────────┘ │    │ └─────────────┘ │    │ └─────────────┘ │
│                 │    │                 │    │                 │
│ ┌─────────────┐ │    │ ┌─────────────┐ │    │ ┌─────────────┐ │
│ │   Escrow    │ │    │ │   Escrow    │ │    │ │ Withdrawal  │ │
│ │  Deposit    │ │    │ │ Management  │ │    │ │   & Claim   │ │
│ └─────────────┘ │    │ └─────────────┘ │    │ └─────────────┘ │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Supported Chains

| Chain | Chain ID | Status |
|-------|----------|--------|
| Monad | 1337* | ✅ Supported |
| Ethereum | 1 | ✅ Supported |
| BSC | 56 | ✅ Supported |
| Polygon | 137 | ✅ Supported |

*Note: Replace with actual Monad chain ID when available

## Smart Contracts

### CrossChainResolver.sol
Main contract for cross-chain order management.

**Key Functions:**
- `createOrder()` - Create a new cross-chain order
- `fillOrder()` - Fill an existing order (authorized resolvers only)
- `cancelOrder()` - Cancel an order
- `deployEscrow()` - Deploy escrow on destination chain
- `withdrawFromEscrow()` - Withdraw from escrow

### Escrow.sol
Escrow contract for secure cross-chain deposits.

**Key Functions:**
- `createEscrow()` - Create a new escrow deposit
- `withdraw()` - Withdraw using secret
- `cancelEscrow()` - Cancel escrow
- `forceWithdraw()` - Force withdrawal (authorized only)

## Installation & Setup

### Prerequisites
- Foundry
- Node.js (for testing)
- Git

### Installation
```bash
# Clone the repository
git clone <repository-url>
cd monad-cross-chain-resolver

# Install dependencies
forge install OpenZeppelin/openzeppelin-contracts
```

### Configuration
1. Set your private key in environment:
```bash
export PRIVATE_KEY=your_private_key_here
```

2. Update Monad chain ID in contracts:
```solidity
// In CrossChainResolver.sol and test files
uint256 public constant MONAD_CHAIN_ID = 1337; // Replace with actual ID
```

## Usage

### Deployment
```bash
# Deploy contracts
forge script script/Deploy.s.sol --rpc-url <your_rpc_url> --broadcast
```

### Testing
```bash
# Run all tests
forge test

# Run specific test
forge test --match-test testCreateOrder

# Run with verbose output
forge test -vvv
```

### Example Usage

#### 1. Create Cross-Chain Order
```solidity
// Create order from Ethereum to Monad
resolver.createOrder{value: 1 ether}(
    1,              // Ethereum chain ID
    1337,           // Monad chain ID
    address(0x123), // Source token
    address(0x456), // Destination token
    1 ether,        // Amount
    block.timestamp + 1 hours // Deadline
);
```

#### 2. Fill Order
```solidity
// Fill order (authorized resolver only)
resolver.fillOrder(orderHash, takerAddress, amount);
```

#### 3. Create Escrow
```solidity
// Create escrow deposit
escrow.createEscrow{value: 1 ether}(
    orderHash,
    recipient,
    secretHash,
    deadline
);
```

#### 4. Withdraw from Escrow
```solidity
// Withdraw using secret
escrow.withdraw(orderHash, secret);
```

## Security Features

### Access Control
- **Ownable**: Contract ownership management
- **Authorized Resolvers**: Whitelist for order execution
- **Modifiers**: Function-level access control

### Reentrancy Protection
- **ReentrancyGuard**: Prevents reentrancy attacks
- **Checks-Effects-Interactions**: Safe state management

### Cryptographic Security
- **Hash-Locked Escrows**: Cryptographic secrets for withdrawals
- **ECDSA**: Digital signature verification
- **Secure Randomness**: Proper secret generation

## Testing

The project includes comprehensive tests covering:
- Order creation and management
- Escrow functionality
- Cross-chain operations
- Security validations
- Access control
- Error handling

Run tests with:
```bash
forge test
```

## Integration with 1inch

This implementation can be integrated with 1inch's cross-chain SDK:

1. **Configure Chain Support**: Add Monad chain to 1inch SDK configuration
2. **Implement Resolver Interface**: Connect with 1inch's resolver interface
3. **Handle Order Flow**: Integrate with 1inch's order management system

### Fusion SDK Integration
For advanced cross-chain functionality, integrate with 1inch's Fusion SDK:

```javascript
// Example integration (pseudo-code)
import { FusionSDK } from '@1inch/fusion-sdk';

const fusionSDK = new FusionSDK({
    chains: {
        monad: {
            chainId: 1337,
            resolver: '0x...',
            escrow: '0x...'
        }
    }
});
```

## Development

### Adding New Chains
1. Update chain constants in `CrossChainResolver.sol`
2. Add chain ID to supported chains mapping
3. Update tests with new chain scenarios
4. Verify chain compatibility

### Customizing Parameters
```solidity
// Update order parameters
resolver.updateOrderParameters(
    0.001 ether,  // Min order amount
    1000 ether,   // Max order amount
    1 hours       // Order timeout
);

// Update escrow parameters
escrow.updateEscrowParameters(
    0.001 ether,  // Min deposit amount
    1000 ether,   // Max deposit amount
    1 hours       // Escrow timeout
);
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Implement changes with tests
4. Submit a pull request

## License

MIT License - see LICENSE file for details

## Support

For questions and support:
- Create an issue in the repository
- Check the documentation
- Review the test cases for examples

## Roadmap

- [ ] Integration with 1inch Fusion SDK
- [ ] Multi-token support
- [ ] Advanced order types
- [ ] Cross-chain messaging
- [ ] Gas optimization
- [ ] Formal verification
