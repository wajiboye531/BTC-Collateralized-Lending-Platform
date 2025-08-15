# 🏦 BTC-Collateralized Lending Platform

A decentralized lending platform built on Stacks that allows users to deposit BTC as collateral and borrow stable assets. The platform enforces interest rates, collateral requirements, and automatic liquidation through smart contracts.

## 🚀 Features

- 💰 **Collateral Deposits**: Deposit BTC to use as loan collateral
- 📈 **Overcollateralized Loans**: Borrow up to 66.67% of collateral value (150% collateral ratio)
- 🔄 **Interest Accrual**: 5% annual interest rate calculated per block
- ⚡ **Liquidation Protection**: Automatic liquidation when collateral ratio drops below 120%
- 💸 **Flexible Repayment**: Partial or full loan repayment options
- 🛡️ **Risk Management**: Built-in safety mechanisms and emergency controls

## 📊 Key Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| Collateral Ratio | 150% | Minimum collateral required |
| Liquidation Threshold | 120% | Ratio triggering liquidation |
| Interest Rate | 5% | Annual interest rate |
| Liquidation Bonus | 10% | Reward for liquidators |

## 🔧 Core Functions

### For Borrowers

#### `deposit-collateral`
```clarity
(deposit-collateral amount)
```
Deposit STX tokens as BTC collateral for future loans.

#### `create-loan`
```clarity
(create-loan collateral-amount)
```
Create a new loan using deposited collateral. Maximum loan amount is collateral ÷ 1.5.

#### `repay-loan`
```clarity
(repay-loan amount)
```
Repay loan principal and accrued interest. Full repayment releases collateral.

#### `withdraw-collateral`
```clarity
(withdraw-collateral amount)
```
Withdraw excess collateral not backing active loans.

### For Liquidators

#### `liquidate-loan`
```clarity
(liquidate-loan borrower)
```
Liquidate undercollateralized loans and earn 10% bonus from collateral.

### Read-Only Functions

#### `get-loan-info`
```clarity
(get-loan-info borrower)
```
Returns comprehensive loan details including debt and liquidation status.

#### `get-user-collateral`
```clarity
(get-user-collateral user)
```
Check user's total deposited collateral.

#### `get-platform-stats`
```clarity
(get-platform-stats)
```
View platform-wide statistics and parameters.

## 💡 Usage Examples

### 1. Basic Lending Flow
```bash
# Deposit 1000 STX as collateral
(contract-call? .btc-lending deposit-collateral u1000)

# Create loan with 800 STX collateral (max ~533 stable tokens)
(contract-call? .btc-lending create-loan u800)

# Repay 100 tokens
(contract-call? .btc-lending repay-loan u100)

# Withdraw unused collateral
(contract-call? .btc-lending withdraw-collateral u200)
```

### 2. Liquidation Scenario
```bash
# Check if loan can be liquidated
(contract-call? .btc-lending get-loan-info 'SP1ABC...)

# Liquidate undercollateralized loan
(contract-call? .btc-lending liquidate-loan 'SP1ABC...)
```

## ⚠️ Risk Factors

- **Price Volatility**: BTC price changes affect collateral ratios
- **Interest Accumulation**: Unpaid interest increases liquidation risk  
- **
