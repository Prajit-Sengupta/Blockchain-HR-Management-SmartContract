// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import {IHumanResources} from "../src/IHumanResources.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../src/IWETH.sol";

contract HumanResources is IHumanResources, ReentrancyGuard{

address public immutable  hrManagerAddr;

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
        } else {
            employees[employee] = Employee({
                weeklyUsdSalary: weeklyUsdSalary,
                employedSince: block.timestamp,
                terminatedAt: 0,
                isETH: false,                // Default to USDC salary
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

function calculateSalary(address employee) internal view returns (uint256) {
        Employee storage emp = employees[employee];
        uint256 timeWorked;
        uint256 totalSalary;

        if (emp.employedSince == 0) {
            return 0;
        }

        if (emp.terminatedAt == 0) {
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
        // Get ETH price in USD 
        uint256 ethPrice = getEthPrice();

        uint256 expectedEth = (totalSalary * 1e18) / ethPrice;

        return expectedEth;
    } else {
        // USDC, scaled to 6 decimals
        return totalSalary / (10 ** 12);
    }
}

function swapUSDCtoETH(uint256 usdcAmount) internal returns (uint256 ethReceived) {
    usdc.approve(UNISWAP_ROUTER, usdcAmount);

    uint256 ethPrice = getEthPrice();

    uint256 usdcAmountWith18Decimals = usdcAmount * 1e12;
    uint256 expectedEth = (usdcAmountWith18Decimals * 1e18) / ethPrice;
    uint256 minEthOut = (expectedEth * 98) / 100; // Slippage of 2%

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

    uint256 wethReceived = swapRouter.exactInputSingle(params);
    require(wethReceived >= minEthOut, "Insufficient ETH received");

    uint256 wethBalance = IWETH(WETH_ADDRESS).balanceOf(address(this));
    require(wethBalance >= wethReceived, "Insufficient WETH balance for withdrawal");

    // Unwrap WETH to get ETH
    IWETH(WETH_ADDRESS).withdraw(wethReceived);
    ethReceived = wethReceived;
}

function withdrawSalary() public nonReentrant{
    Employee storage emp = employees[msg.sender];

    //Should be registerd (Either Active or Terminated)
     if (emp.employedSince == 0){
        revert NotAuthorized();
    }

    uint256 availableSalary = calculateSalary(msg.sender);
    require(availableSalary >= 0, "No salary available for withdrawal");

    // To check if the employee prefers ETH or USDC
    if (emp.isETH) {
        uint256 ethAmount = swapUSDCtoETH(availableSalary/(10**12));
        (bool success, ) = msg.sender.call{value: ethAmount}("");
        require(success, "ETH transfer failed");

        emit SalaryWithdrawn(msg.sender, emp.isETH, ethAmount);
    } else {
        require(usdc.transfer(msg.sender, availableSalary / (10 ** 12)), "USDC transfer failed");
        emit SalaryWithdrawn(msg.sender, emp.isETH, availableSalary / (10 ** 12));
    }
    emp.lastWithdrawnAt = block.timestamp;
    emp.unclaimedSalary = 0;
}

function switchCurrency() external onlyEmployee{
    Employee storage emp = employees[msg.sender];
    require(emp.employedSince != 0 && emp.terminatedAt==0, "Employee not registered");
    withdrawSalary();
    emp.isETH = !emp.isETH;
    emit CurrencySwitched(msg.sender, emp.isETH);
}

function getCurrencyPreference(address employee) external view returns (bool) {
    require(employees[employee].employedSince > 0, "Employee not registered");
    return employees[employee].isETH;
}

receive() external payable {}

}
