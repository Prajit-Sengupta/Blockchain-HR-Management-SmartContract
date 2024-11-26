// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import {IHumanResources} from "../src/IHumanResources.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "../src/IWETH.sol";

contract HumanResources is IHumanResources{

address public immutable  hrManagerAddr;

uint256 public constant DECIMALS = 18;  // Scaling factor
uint256 public constant SCALING_FACTOR = 10**DECIMALS;

uint256 public activeEmployeeCount;

address public constant USDC_ADDRESS = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85; // USDC on Optimism
address public constant WETH_ADDRESS = 0x4200000000000000000000000000000000000006; // WETH on Optimism

address public constant UNISWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564; // Uniswap Router
address public constant CHAINLINK_ORACLE = 0x13e3Ee699D1909E989722E753853AE30b17e08c5; // Chainlink ETH/USD

AggregatorV3Interface private priceFeed;
ISwapRouter private swapRouter;
IERC20 private usdc;

constructor( ){

    hrManagerAddr = msg.sender;
    priceFeed = AggregatorV3Interface(CHAINLINK_ORACLE);
    swapRouter = ISwapRouter(UNISWAP_ROUTER);
    usdc = IERC20(USDC_ADDRESS);

}

modifier onlyHRManager(){
    if (msg.sender != hrManagerAddr){
        revert NotAuthorized();
    }
    _;
}

mapping(address => Employee) public employees;
struct Employee {
    uint256 weeklyUsdSalary;
    uint256 employedSince;
    uint256 terminatedAt;
    uint256 lastWithdrawnAt;
    uint256 unclaimedSalary;
    bool isETH;
}

modifier onlyEmployee() {
    if (employees[msg.sender].employedSince == 0 || employees[msg.sender].terminatedAt != 0){
        revert NotAuthorized();
    }
    _;
}

function hrManager() external view returns (address){
    return hrManagerAddr;
}

function calculateSalary(address employee) internal view returns (uint256) {
        Employee storage emp = employees[employee];
        uint256 timeWorked;
        uint256 totalSalary;

        if (emp.employedSince == 0) {
            return 0;
        }

        if (emp.terminatedAt == 0) {
            // Employee is active, calculate up to current time
            timeWorked = block.timestamp - emp.lastWithdrawnAt;
            uint256 accruedSalary = (emp.weeklyUsdSalary * timeWorked) / (7 days);
            totalSalary = accruedSalary + emp.unclaimedSalary;
        } else {
            totalSalary = emp.unclaimedSalary;
        }
        return totalSalary;
}
function salaryAvailable(address employee) public view returns (uint256) {
    Employee storage emp = employees[employee];
    uint256 totalSalary = calculateSalary(employee);

    if (emp.isETH) {
        // Get ETH price in USD with 18 decimals
        uint256 ethPrice = getEthPrice();

        // Convert the total salary from USD to ETH
        // totalSalary is in USD with 18 decimals, ethPrice is in USD with 18 decimals
        uint256 expectedEth = (totalSalary * 1e18) / ethPrice;

        return expectedEth;
    } else {
        // If employee prefers USDC, scale it to 6 decimals
        return totalSalary / (10 ** 12);
    }
}

// function salaryAvailable(address employee) public view returns (uint256){
//         Employee storage emp = employees[employee];
//         uint256 totalSalary = calculateSalary(employee);
//         if (emp.isETH) {
//             uint256 ethPrice = getEthPrice();
//             uint256 usdcAmountWith18Decimals = totalSalary; 
//             uint256 adjustedEthPrice = ethPrice * 1e10;
//             uint256 expectedEth = (usdcAmountWith18Decimals) / adjustedEthPrice;
//             return expectedEth;
//         } else {
//             // If employee prefers USDC, scale it to 6 decimals
//             return totalSalary / (10 ** 12);
//         }
// }

function registerEmployee(address employee, uint256 weeklyUsdSalary) external onlyHRManager{

        if (employees[employee].employedSince != 0 && employees[employee].terminatedAt == 0) {
            revert EmployeeAlreadyRegistered();
        }

        if (employees[employee].employedSince != 0 && employees[employee].terminatedAt != 0) {
            employees[employee].weeklyUsdSalary = weeklyUsdSalary;
            employees[employee].employedSince = block.timestamp;
            employees[employee].lastWithdrawnAt = block.timestamp;
            employees[employee].terminatedAt = 0;
            employees[employee].isETH = false;   
                          // Set terminatedAt to zero to indicate active status again
        } else {
            employees[employee] = Employee({
                weeklyUsdSalary: weeklyUsdSalary,
                employedSince: block.timestamp,
                terminatedAt: 0,
                isETH: false, // Default to USDC salary
                unclaimedSalary: 0,
                lastWithdrawnAt: block.timestamp
            });
             }

        activeEmployeeCount++;
        emit EmployeeRegistered(employee, weeklyUsdSalary);
  }


function terminateEmployee(address employee) external onlyHRManager{
    if (employees[employee].employedSince == 0 || employees[employee].terminatedAt != 0) {
            revert EmployeeNotRegistered();
    }

    employees[employee].terminatedAt = block.timestamp;
    uint256 timeWorked = block.timestamp - employees[employee].lastWithdrawnAt;
    uint256 unclaimed = (employees[employee].weeklyUsdSalary * timeWorked) / (7 days);
    employees[employee].unclaimedSalary = unclaimed;
    activeEmployeeCount--;
    emit EmployeeTerminated(employee);

}


function getActiveEmployeeCount() external view returns (uint256){
    return activeEmployeeCount;
}

 function getEmployeeInfo(address employee) external view returns (
            uint256 weeklyUsdSalary,
            uint256 employedSince,
            uint256 terminatedAt
        ){
            Employee storage emp = employees[employee];

             if (emp.employedSince == 0) {
                return (0, 0, 0);
             }
            return (emp.weeklyUsdSalary, emp.employedSince, emp.terminatedAt);
        }


function getEthPrice() public view returns (uint256) {
        (, int256 price,,,) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price data");
        uint256 feedDecimals = priceFeed.decimals();
        return uint256(price) * 10 ** (18 - feedDecimals); 
}

// function swapUSDCtoETH(uint256 usdcAmount) internal returns (uint256 ethReceived) {
//         usdc.approve(UNISWAP_ROUTER, usdcAmount);
//         // Get ETH price in USD with 18 decimals
//         uint256 ethPrice = getEthPrice();
//         uint256 totalSalary = usdcAmount*1e12;
//         // Convert the total salary from USD to ETH
//         // totalSalary is in USD with 18 decimals, ethPrice is in USD with 18 decimals
//         uint256 expectedEth = (totalSalary * 1e18) / ethPrice;
//         uint256 minEthOut = (expectedEth * 98) / 100;

//         ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
//             tokenIn: USDC_ADDRESS,
//             tokenOut: WETH_ADDRESS,
//             fee: 500,
//             recipient: address(this),
//             deadline: block.timestamp + 15,
//             amountIn: usdcAmount,
//             amountOutMinimum: minEthOut,
//             sqrtPriceLimitX96: 0
//         });

//         ethReceived = swapRouter.exactInputSingle(params);
//         require(ethReceived >= minEthOut, "Insufficient ETH received");
// }
function swapUSDCtoETH(uint256 usdcAmount) internal returns (uint256 ethReceived) {
    // Approve the Uniswap Router to spend the specified USDC amount
    usdc.approve(UNISWAP_ROUTER, usdcAmount);

    // Get the current ETH price in USD with 18 decimals
    uint256 ethPrice = getEthPrice();

    // Convert the USDC amount from 6 decimals to 18 decimals
    uint256 usdcAmountWith18Decimals = usdcAmount * 1e12;

    // Calculate the amount of ETH that can be obtained from the given USDC
    // totalSalary is in USD with 18 decimals, ethPrice is in USD with 18 decimals
    uint256 expectedEth = (usdcAmountWith18Decimals * 1e18) / ethPrice;
    uint256 minEthOut = (expectedEth * 98) / 100; // Allow for slippage of 2%

    // Set up parameters for the Uniswap swap
    ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
        tokenIn: USDC_ADDRESS,
        tokenOut: WETH_ADDRESS,
        fee: 500,
        recipient: address(this),
        deadline: block.timestamp + 15,
        amountIn: usdcAmount,
        amountOutMinimum: minEthOut,
        sqrtPriceLimitX96: 0
    });

    // Perform the swap and get the amount of WETH received
    uint256 wethReceived = swapRouter.exactInputSingle(params);
    require(wethReceived >= minEthOut, "Insufficient ETH received");

    // Check if the contract has enough WETH balance
    uint256 wethBalance = IWETH(WETH_ADDRESS).balanceOf(address(this));
    require(wethBalance >= wethReceived, "Insufficient WETH balance for withdrawal");

    // Unwrap WETH to get ETH
    IWETH(WETH_ADDRESS).withdraw(wethReceived);

    ethReceived = wethReceived;
}

function withdrawSalary() public onlyEmployee() {
    Employee storage emp = employees[msg.sender];
    
    // Fetch the available salary for the employee
    uint256 availableSalary = calculateSalary(msg.sender);
    require(availableSalary >= 0, "No salary available for withdrawal");
    // Check if the employee prefers ETH or USDC
    if (emp.isETH) {
            // If employee prefers ETH, swap USDC for ETH and transfer
        uint256 ethAmount = swapUSDCtoETH(availableSalary/(10**12));
        (bool success, ) = msg.sender.call{value: ethAmount}("");

        emit SalaryWithdrawn(msg.sender, true, ethAmount);
    } else {
            // If employee prefers USDC, transfer the amount in USDC
            require(usdc.transfer(msg.sender, availableSalary / (10 ** 12)), "USDC transfer failed");
            emit SalaryWithdrawn(msg.sender, false, availableSalary / (10 ** 12));
    }
    emp.lastWithdrawnAt = block.timestamp;
    emp.unclaimedSalary = 0;
}


function switchCurrency() external {
    // Ensure the employee is registered and active
    Employee storage emp = employees[msg.sender];
    require(emp.employedSince != 0, "Employee not registered");

    // Step 1: Call withdrawSalary to withdraw the current accumulated salary
    withdrawSalary();

    // Step 2: Toggle the preferred currency
    emp.isETH = !emp.isETH;

    // Step 3: Emit the CurrencySwitched event
    emit CurrencySwitched(msg.sender, emp.isETH);
}
receive() external payable {}

}
