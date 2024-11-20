// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import {IHumanResources} from "src/IHumanResources.sol";



contract HumanResources is IHumanResources{

address public immutable  hrManager;

uint256 public constant DECIMALS = 18;  // Scaling factor
uint256 public constant SCALING_FACTOR = 10**DECIMALS;

uint256 public activeEmployeeCount;

constructor(){
    hrManager == msg.sender;
}

modifier onlyHRManager(){
    if (msg.sender != hrManager){
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

function registerEmployee(address employee, uint256 weeklyUsdSalary) external onlyHRManager{

        if (employees[employee].employedSince != 0 && employees[employee].terminatedAt == 0) {
            revert EmployeeAlreadyRegistered();
        }

        if (employees[employee].employedSince != 0 && employees[employee].terminatedAt != 0) {
            
            //Unclaimed salary while registering
            uint256 unclaimed = salaryAvailable(employee);
            employee.unclaimedSalary += unclaimed;

            employees[employee].employedSince = block.timestamp;  // Set employment start to current time
            employees[employee].terminatedAt = 0;                 // Set terminatedAt to zero to indicate active status again
        } else {

            employees[employee] = Employee({
                weeklyUsdSalary: weeklyUsdSalary * SCALING_FACTOR,
                employedSince: block.timestamp,
                terminatedAt: 0
                isEth: false // Default to USDC salary
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

function withdrawSalary() external onlyEmployee{
    Employee storage emp = employees[msg.sender];
    uint256 timeWorked = block.timestamp - emp.employedSince;

}

function salaryAvailable(address employee) external view returns (uint256){
    Employee storage emp = employees[msg.sender];
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

    if (emp.isEth) {
        // If employee prefers ETH, keep the amount in 18 decimals
        return totalSalary;
    } else {
        // If employee prefers USDC, scale it to 6 decimals
        return totalSalary / (10 ** 12);
    }

    
}
   
//Add condition where no to emit when currency to withddarw is zero
    










    
}
