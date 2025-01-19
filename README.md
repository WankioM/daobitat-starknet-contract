# StarkLeasing

Smart contracts for decentralized property rental management built on StarkNet.

## Overview

StarkLeasing is a protocol that enables property owners and tenants to create, manage, and execute rental agreements on StarkNet with built-in escrow functionality.

### Core Features

- Property registration and management
- Automated rental agreements
- Secure escrow system
- Dispute resolution mechanism
- ERC20 payment support

## Contract Structure

- `RentalRegistry`: Property management and ownership tracking
- `RentalAgreement`: Agreement creation and escrow handling
- `SharedTypes`: Common types used across contracts

## Development

```bash
# Install dependencies
scarb install

# Build contracts
scarb build

# Run tests
scarb test
```

## Prerequisites

- [Scarb](https://docs.swmansion.com/scarb)
- [StarkNet Foundry](https://foundry-rs.github.io/starknet-foundry/)

## License

MIT