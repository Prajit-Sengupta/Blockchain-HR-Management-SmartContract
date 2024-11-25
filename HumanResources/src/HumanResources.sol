// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import {IHumanResources} from "../src/IHumanResources.sol";

// import "../../node_modules/@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
// import "../../node_modules/@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
// import "../../node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";



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

    hrManagerAddr == msg.sender;
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


function salaryAvailable(address employee) public view returns (uint256){
    Employee storage emp = employees[employee];
    uint256 timeWorked;

    if (emp.employedSince == 0) {
        return 0;
    }
    if (emp.terminatedAt == 0) {
        // The employee is active and currently working
        timeWorked = block.timestamp - emp.employedSince;
    } else {
        // The employee was terminated; calculate until termination time
        timeWorked = emp.terminatedAt - emp.employedSince;
    }

    uint256 accruedSalary = (emp.weeklyUsdSalary * timeWorked) / (7 days);
    uint256 totalSalary = accruedSalary + emp.unclaimedSalary;

    if (emp.isETH) {
        // If employee prefers ETH, keep the amount in 18 decimals
        return totalSalary;
    } else {
        // If employee prefers USDC, scale it to 6 decimals
        return totalSalary / (10 ** 12);
    }
}

function registerEmployee(address employee, uint256 weeklyUsdSalary) external onlyHRManager{

        if (employees[employee].employedSince != 0 && employees[employee].terminatedAt == 0) {
            revert EmployeeAlreadyRegistered();
        }

        if (employees[employee].employedSince != 0 && employees[employee].terminatedAt != 0) {
            
            //Unclaimed salary while registering
            uint256 unclaimed = salaryAvailable(employee);
            employees[employee].unclaimedSalary += unclaimed;

            employees[employee].employedSince = block.timestamp;  // Set employment start to current time
            employees[employee].terminatedAt = 0;                 // Set terminatedAt to zero to indicate active status again
        } else {

            employees[employee] = Employee({
                weeklyUsdSalary: weeklyUsdSalary * SCALING_FACTOR,
                employedSince: block.timestamp,
                terminatedAt: 0,
                isETH: false, // Default to USDC salary
                unclaimedSalary: 0
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
    return uint256(price) * 1e10; // Convert to 18 decimals
}

function swapUSDCtoETH(uint256 usdcAmount) internal returns (uint256 ethReceived) {
    // Approve USDC for the Uniswap router
    usdc.approve(UNISWAP_ROUTER, usdcAmount);

    // Minimum ETH amount based on the price feed and 2% slippage tolerance
    uint256 ethPrice = getEthPrice(); // ETH/USD
    uint256 expectedEth = (usdcAmount * 1e18) / ethPrice; // USDC to ETH conversion
    uint256 minEthOut = (expectedEth * 98) / 100; // Allow 2% slippage

    // Execute the swap
    ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
        tokenIn: USDC_ADDRESS,
        tokenOut: WETH_ADDRESS,
        fee: 3000, // Pool fee
        recipient: address(this),
        deadline: block.timestamp + 15,
        amountIn: usdcAmount,
        amountOutMinimum: minEthOut,
        sqrtPriceLimitX96: 0
    });

    ethReceived = swapRouter.exactInputSingle(params);

    require(ethReceived >= minEthOut, "Insufficient ETH received");
}


function withdrawSalary() public onlyEmployee() onlyHRManager(){
    // Validate that the caller is either an active employee or the HR manager
    //nonReentrant - later add it
    Employee storage emp = employees[msg.sender];

    
    // Fetch the available salary for the employee
    uint256 availableSalary = salaryAvailable(msg.sender);
    
    // Reset the unclaimed salary after it is withdrawn
    emp.unclaimedSalary = 0;

    // Check if the employee prefers ETH or USDC
    if (emp.isETH) {
        // If employee prefers ETH, swap USDC for ETH and transfer
        uint256 ethAmount = swapUSDCtoETH(availableSalary);

        // Transfer the ETH to the employee
        (bool success, ) = msg.sender.call{value: ethAmount}("");
        require(success, "ETH transfer failed");

        // Emit event for ETH withdrawal
        emit SalaryWithdrawn(msg.sender, true, ethAmount);
    } else {
        // If employee prefers USDC, transfer the amount in USDC
        require(usdc.transfer(msg.sender, availableSalary), "USDC transfer failed");

        // Emit event for USDC withdrawal
        emit SalaryWithdrawn(msg.sender, false, availableSalary);
    }
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





   
//Add condition where no to emit when currency to withddarw is zero
// What functioms its importing 
}
