# HumanResources Contract Documentation

## Overview
The `HumanResources` contract provides a human resources payment system where employees can be registered, terminated, and paid in either USDC or ETH based on their preference. The HR manager, specified upon contract deployment, is responsible for managing employees. This contract is designed to be deployed on the Optimism network and uses Chainlink oracles for fetching ETH/USD prices and Uniswap AMM for converting USDC to ETH.

### Key Functionalities
- **Role Management**: Only the HR manager can register or terminate employees.
- **Salary Payments**: Employees can withdraw accumulated salaries in USDC or ETH based on their preference.
- **Oracle Integration**: The contract uses Chainlink to fetch the latest ETH/USD price.
- **AMM Integration**: Uses Uniswap to convert USDC to ETH when an employee opts to receive their salary in ETH.
- **Reentrancy Protection**: Withdrawals are protected against reentrancy attacks using OpenZeppelin's `ReentrancyGuard`.

## Assumptions
For the purpose of this coursework, we assume that **1 USD = 1 USDC**.

## Default Currency
- By default, the salary is paid in **USDC** unless the employee explicitly switches their preference to ETH.

## Functions Implemented from `IHumanResources`
### 1. `registerEmployee(address employee, uint256 weeklyUsdSalary)`
- **Purpose**: Registers an employee with a specified weekly salary.
- **Access Control**: Can only be called by the HR manager.
- **Events**: Emits `EmployeeRegistered` when a new employee is registered.
- **Error Handling**: Reverts if the employee is already registered and not terminated.

### 2. `terminateEmployee(address employee)`
- **Purpose**: Terminates an employee, stopping salary accrual.
- **Access Control**: Can only be called by the HR manager.
- **Events**: Emits `EmployeeTerminated` when an employee is terminated.
- **Error Handling**: Reverts if the employee is not registered or has already been terminated.

### 3. `withdrawSalary()`
- **Purpose**: Allows employees to withdraw their accumulated salary in USDC or ETH.
- **Access Control**: Only callable by registered employees.
- **Logic**:
  - If the employee prefers ETH, the contract uses Uniswap to swap USDC to ETH.
  - ETH is sent using a re-entrancy safe method.
  - If the employee prefers USDC, it directly transfers USDC.
- **Events**: Emits `SalaryWithdrawn` with the currency type (ETH or USDC).
- **Reentrancy Protection**: Utilizes `nonReentrant` modifier to prevent reentrancy attacks.

### 4. `switchCurrency()`
- **Purpose**: Allows an employee to switch between receiving salary in USDC or ETH.
- **Access Control**: Only callable by registered employees.
- **Logic**:
  - Withdraws the accumulated salary before switching the preferred currency.
  - Toggles the currency preference and emits `CurrencySwitched`.
- **Events**: Emits `CurrencySwitched` when the preferred currency changes.

### 5. `salaryAvailable(address employee)`
- **Purpose**: Returns the current accumulated salary available for withdrawal.
- **Access Control**: View function that can be called by anyone.
- **Logic**:
  - Calculates the salary in the preferred currency (USDC or ETH).
  - If ETH is preferred, it uses the Chainlink price feed to determine the equivalent ETH amount.

### 6. `getEmployeeInfo(address employee)`
- **Purpose**: Provides information about an employee's salary, registration, and termination status.
- **Access Control**: View function accessible to anyone.
- **Logic**:
  - Returns weekly salary, registration timestamp, and termination timestamp (if applicable).

### 7. `getActiveEmployeeCount()`
- **Purpose**: Returns the number of active employees in the system.
- **Access Control**: View function accessible to anyone.

### 8. `hrManager()`
- **Purpose**: Returns the address of the HR manager.
- **Access Control**: View function accessible to anyone.
- **Logic**: 
  - The `hrManagerAddr` is the address of the HR Manager set during contract deployment.

### 9. `getCurrencyPreference(address employee)`
- **Purpose**: Returns the preferred currency of the specified employee (USDC or ETH).
- **Access Control**: View function accessible to anyone.
- **Logic**:
  - Checks if the employee is registered and returns their preferred currency.

## Integration with AMM and Oracle
### Chainlink Oracle Integration
- The contract integrates with the Chainlink ETH/USD price feed at address `0x13e3Ee699D1909E989722E753853AE30b17e08c5`.
- **Function Used**: `getEthPrice()` fetches the latest price to convert USDC to ETH when an employee chooses to receive salary in ETH.
- **Function Description**:
  - **`getEthPrice()`**: Fetches the latest ETH price from the Chainlink oracle and returns it in 18 decimal format for consistency. This function includes error handling to ensure a valid price is always returned.

### Uniswap AMM Integration
- The contract uses Uniswap's swap router (`0xE592427A0AEce92De3Edee1F18E0157C05861564`) to convert USDC to ETH.
- **Function Used**: `swapUSDCtoETH(uint256 usdcAmount)` swaps a specified amount of USDC to ETH.
- **Function Description**:
  - **`swapUSDCtoETH(uint256 usdcAmount)`**: Uses the Uniswap Router to swap USDC for ETH. The function takes care of converting USDC to ETH, considering a 2% slippage tolerance, and unwraps WETH to obtain ETH.
- **Slippage Protection**: The swap includes a minimum amount of ETH expected, set to be at least 98% of the calculated value to prevent front-running and excessive slippage.

### IWETH
- The Uniswap swap provides WETH (Wrapped ETH) instead of direct ETH. To ensure that employees receive native ETH when they request it, the contract uses `IWETH` to unwrap WETH into ETH. This allows for easier and more consistent interactions when paying employees who opt for ETH.

## Additional Function Descriptions
### `calculateSalary(address employee)`
- **Purpose**: Calculates the total accrued salary for an employee.
- **Logic**:
  - If the employee is active, it calculates the salary accrued from the last updated time until the current time.
  - If the employee is terminated, it only returns the unclaimed salary.
  - The function considers weekly salary, time worked, and unclaimed salary.
  - Returns the calculated salary in 18 decimals for consistency.

## Security Features
- **Role-based Access Control**: Uses modifiers like `onlyHRManager` and `onlyEmployee` to restrict access to critical functions.
- **ReentrancyGuard**: The `withdrawSalary()` function is protected with `nonReentrant` to prevent reentrancy attacks.
- **ETH Transfers**: Uses safe methods for ETH transfers to prevent reentrancy.

## Summary
The `HumanResources` contract provides a complete HR payment solution on Optimism, enabling role-based access, flexible salary withdrawal in multiple currencies, and secure interaction with external DeFi protocols for swapping and price feeds. The integration with Chainlink ensures accurate pricing, and Uniswap allows seamless conversion of USDC to ETH, while security is maintained using OpenZeppelin's `ReentrancyGuard` and proper access control mechanisms.

