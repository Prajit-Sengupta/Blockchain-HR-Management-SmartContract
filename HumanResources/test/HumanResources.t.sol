// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/HumanResources.sol";
import "../src/IHumanResources.sol";
import "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol"; // Mock for ChainLink
import "../test/MockERC20.sol"; // Assuming MockERC20 is used for USDC
import "../test/UniswapRouterMock.sol"; // Mock for Uniswap Router
import "forge-std/console.sol";

contract HumanResourcesTest is Test {
    HumanResources public hrContract;
    MockERC20 public usdc;
    MockERC20 public weth;
    MockV3Aggregator public chainlinkOracle;
    UniswapRouterMock public uniswapRouter;

    address public hrManager = address(0x123);
    address public employee1 = address(0x456);
    address public employee2 = address(0x789);
    address unauthorizedAddress = address(4);

    uint256 public Salary = 5000; // 5000 USD scaled to 18 decimals

    event EmployeeRegistered(address indexed employee, uint256 weeklyUsdSalary);
    event EmployeeTerminated(address indexed employee);
    event SalaryWithdrawn(address indexed employee, bool isEth, uint256 amount);
    event CurrencySwitched(address indexed employee, bool isEth);

    function setUp() public {
        // Deploy mock tokens
        usdc = new MockERC20("USDC", "USDC", 6); 
        weth = new MockERC20("Wrapped ETH", "WETH", 18);

        // Deploy mock Chainlink Oracle and Uniswap Router
        chainlinkOracle = new MockV3Aggregator(18, 2000 * 10 ** 8);
        uniswapRouter = new UniswapRouterMock();

        vm.prank(hrManager);
        // Deploy HumanResources contract
        hrContract = new HumanResources();

        // Mint and fund tokens
        usdc.mint(hrManager, 100000 * 10 ** 6);  // Mint USDC for HR manager
        usdc.mint(employee1, 100000 * 10 ** 6);  // Mint USDC for employee1
    }


function testRegisterEmployee() public {
        // Register an employee with a weekly salary of 1000 USDC (scaled to 18 decimals)
        vm.startPrank(hrManager);
        hrContract.registerEmployee(employee1, 1000);
        vm.stopPrank();

        // Check that the employee details are set correctly
        (uint256 weeklyUsdSalary, uint256 employedSince, uint256 terminatedAt) = hrContract.getEmployeeInfo(employee1);
        
        assertEq(weeklyUsdSalary, 1000 * 10**18, "Employee salary should be 1000 USDC scaled to 18 decimals");
        assertGt(employedSince, 0, "Employee should be registered with a non-zero start date");
        assertEq(terminatedAt, 0, "Employee should be active (termination date should be 0)");
        
        // Check that the active employee count is now 1
        assertEq(hrContract.getActiveEmployeeCount(), 1, "Active employee count should be 1");

        // Unauthorized attempt to register another employee
        vm.startPrank(unauthorizedAddress);
        vm.expectRevert(IHumanResources.NotAuthorized.selector);
        hrContract.registerEmployee(employee2, 500 );
        vm.stopPrank();

        // HR Manager registers another employee
        vm.startPrank(hrManager);
        hrContract.registerEmployee(employee2, 500 );
        vm.stopPrank();

        // Check the new employee's details
        (uint256 weeklyUsdSalaryAnother, uint256 employedSinceAnother, uint256 terminatedAtAnother) = hrContract.getEmployeeInfo(employee2);
        
        assertEq(weeklyUsdSalaryAnother, 500 * 10**18 , "Another employee salary should be 500 USDC scaled to 18 decimals");
        assertGt(employedSinceAnother, 0, "Another employee should be registered with a non-zero start date");
        assertEq(terminatedAtAnother, 0, "Another employee should be active (termination date should be 0)");

        // Check that the active employee count is now 2
        assertEq(hrContract.getActiveEmployeeCount(), 2, "Active employee count should be 2");

        // Terminate an employee and then re-register
        vm.startPrank(hrManager);
        hrContract.terminateEmployee(employee1);
        vm.stopPrank();

        // Ensure employee is terminated
        (, , uint256 terminatedAtAfterTermination) = hrContract.getEmployeeInfo(employee1);
        assertGt(terminatedAtAfterTermination, 0, "Employee should have a termination date after being terminated");

        // Re-register the same employee
        vm.startPrank(hrManager);
        hrContract.registerEmployee(employee1, 1200); // Update salary during re-registration
        vm.stopPrank();

        // Check the re-registered employee details
        (uint256 reRegisteredSalary, uint256 reRegisteredSince, uint256 reRegisteredTerminatedAt) = hrContract.getEmployeeInfo(employee1);
        assertEq(reRegisteredSalary, 1200 * 10**18, "Employee re-registered salary should be updated to 1200 USDC scaled to 18 decimals");
        // assertGt(reRegisteredSince, terminatedAtAfterTermination, "Re-registered start date should be after termination date");
        assertEq(reRegisteredTerminatedAt, 0, "Re-registered employee should be active again (termination date should be 0)");

        // Active employee count should be 2 again
        assertEq(hrContract.getActiveEmployeeCount(), 2, "Active employee count should still be 2 after re-registering");
    }

    function testRegisterEmployeeUnauthorized() public {
        // Attempt to register an employee as a non-HR manager
        vm.prank(employee2);
        vm.expectRevert(abi.encodeWithSelector(IHumanResources.NotAuthorized.selector));
        hrContract.registerEmployee(employee1, Salary);
    }

    function testTerminateEmployee() public {
        
        // Register and terminate an employee
        vm.prank(hrManager);
        hrContract.registerEmployee(employee1, Salary);
        vm.prank(hrManager);
        vm.expectEmit(true, true, false, false);
        emit EmployeeTerminated(employee1);
        hrContract.terminateEmployee(employee1);

        // Verify termination
        (, , uint256 terminatedAt) = hrContract.getEmployeeInfo(employee1);
        assertGt(terminatedAt, 0, "Termination timestamp should be set");
    }

    function testTerminateEmployeeUnauthorized() public {
        // Attempt to terminate an employee as a non-HR manager
        vm.prank(employee2);
        vm.expectRevert(abi.encodeWithSelector(IHumanResources.NotAuthorized.selector));
        hrContract.terminateEmployee(employee1);
    }

    // function testWithdrawSalaryInUSDC() public {
    //     // Register employee and accrue salary
    //     vm.prank(hrManager);
    //     hrContract.registerEmployee(employee1, Salary);

    //     // Advance time to simulate salary accrual
    //     vm.warp(block.timestamp + 7 days); // Advance 7 days

    //     // Employee withdraws salary
    //     vm.prank(employee1);
    //     vm.expectEmit(true, true, false, true);
    //     emit SalaryWithdrawn(employee1, false, Salary / (10 ** 12)); // Adjust to 6 decimals
    //     hrContract.withdrawSalary();

    //     // Verify USDC balance
    //     assertEq(usdc.balanceOf(employee1), Salary / (10 ** 12), "Incorrect USDC balance");
    // }

    function testWithdrawSalaryInETH() public {
        // Register employee and switch to ETH
        vm.prank(hrManager);
        hrContract.registerEmployee(employee1, Salary);

        vm.prank(employee1);
        // hrContract.switchCurrency(); // Switch to ETH

        // Advance time to simulate salary accrual
        vm.warp(block.timestamp + 7 days); // Advance 7 days

        // Employee withdraws salary
        uint256 initialEthBalance = employee1.balance;
        // vm.prank(employee1);
        vm.expectEmit(true, true, true, true);
        emit SalaryWithdrawn(employee1, true, Salary); // Assuming mock returns 0
        hrContract.withdrawSalary();

        // Verify ETH balance (mock value for simplicity)
        uint256 ethBalanceAfter = employee1.balance;
        assertGt(ethBalanceAfter, initialEthBalance, "ETH balance should increase");
        // vm.expectRevert(abi.encodeWithSelector(IHumanResources.NotAuthorized.selector));
    }

    function testWithdrawSalaryInUSDC() public {

        vm.prank(hrManager);
        hrContract.registerEmployee(employee1, Salary);

        // Fast forward time by 4 days to accumulate salary
        vm.warp(block.timestamp + 4 days);

        // Calculate the expected accrued salary after 4 days
        uint256 expectedSalary = (Salary * 4 days) / (7 days);

        // Set the expectation that the `SalaryWithdrawn` event will be emitted with specific values
        vm.expectEmit(true, true, true, true);
        emit SalaryWithdrawn(employee1, false, expectedSalary);

        // Employee withdraws salary in USDC
        vm.prank(employee1);
        hrContract.withdrawSalary();

        // Verify that the unclaimed salary is now zero after withdrawal
        (, , , uint256 unclaimedSalary, ) = hrContract.employees(employee1);
        assertEq(unclaimedSalary, 0, "Unclaimed salary should be zero after withdrawal");

    
    }

    function testSwitchCurrency() public {
        vm.warp(block.timestamp + 3 days);
        // Register an employee
        vm.prank(hrManager);
        hrContract.registerEmployee(employee1, Salary);

        // Switch currency to ETH
        vm.prank(employee1);
        vm.expectEmit(true, true, true, true);
        emit SalaryWithdrawn(employee1, false, hrContract.salaryAvailable(employee1));
        emit CurrencySwitched(employee1, true);
        hrContract.switchCurrency();

        // Verify currency preference
        (, , , , bool isETH) = hrContract.employees(employee1);
        assertTrue(isETH, "Employee should now prefer ETH");
    }

    function testSalaryAvailable() public {
        vm.prank(hrManager);
        hrContract.registerEmployee(employee1, Salary);
        // Fast forward time by 3.5 days
        uint256 timeToFastForward = 3.5 days;
        vm.warp(block.timestamp + timeToFastForward);

        // Calculate the expected accrued salary for 3.5 days
        uint256 expectedSalary = (Salary * 3.5 days) / (7 days);

        // Get the actual available salary
        uint256 availableSalary = hrContract.salaryAvailable(employee1);

        assertEq(availableSalary, expectedSalary * (10 ** 6), "Salary available should be correctly accrued after 3.5 days");
    }

    function testUnauthorizedWithdraw() public {
        // Attempt to withdraw salary as an unauthorized user
        vm.prank(employee2);
        vm.expectRevert(abi.encodeWithSelector(IHumanResources.NotAuthorized.selector));
        hrContract.withdrawSalary();
    }

    receive() external payable {} // Allow the contract to receive ETH
}
