# Titats - ckBTC Tip Jar Platform
Encode Hackathon

Embeddable tip jar widgets powered by ckBTC on the Internet Computer.

## Features

- Instant tips — 1-2 second finality with 10 satoshi fees
- No bridges — Native Bitcoin via chain-key cryptography
- Embeddable widgets — Drop into any website
- 2% platform fee — Configurable by admin
- Full analytics — Track tips, top supporters, goals

## Architecture

Main.mo (Gateway)
    ├── Registry.mo  — Creators & tip jars
    ├── Treasury.mo  — ckBTC payments & withdrawals
    └── History.mo   — Tip history & analytics

## Quick Start

# Clone and enter directory
git clone https://github.com/yourusername/titats
cd titats

# Deploy locally
dfx start --background
./deploy.sh

## Usage

# Register as creator
dfx canister call main registerCreator '(record { 
  username = "alice"; 
  displayName = "Alice"; 
  bio = "Creator"; 
  avatarUrl = "" 
})'

# Create tip jar
dfx canister call main createTipJar '(record { 
  name = "Coffee Fund"; 
  description = "Buy me a coffee!"; 
  targetAmount = opt 100000; 
  suggestedAmounts = vec { 1000; 5000; 10000 }; 
  thankYouMessage = "Thanks!"; 
  widgetTheme = record { 
    primaryColor = "#FF6B00"; 
    backgroundColor = "#FFFFFF"; 
    textColor = "#000000"; 
    borderRadius = 8 
  } 
})'

# Check balance
dfx canister call main getMyBalance

# Withdraw
dfx canister call main withdraw '(50000, record { 
  owner = principal "your-wallet-principal"; 
  subaccount = null 
})'

## Tip Flow

1. Tipper approves ckBTC spend via icrc2_approve
2. Calls sendTip with jar ID and amount
3. Treasury transfers ckBTC, deducts 2% fee
4. Creator balance updated, tip recorded in history
5. Creator withdraws anytime to their wallet

## Tech Stack

- Motoko — Canister smart contracts
- ckBTC — ICRC-1/2 compliant Bitcoin twin
- Internet Identity — Passwordless auth

## License

MIT