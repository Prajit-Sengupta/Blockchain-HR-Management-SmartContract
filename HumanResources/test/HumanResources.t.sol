// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/HumanResources.sol";
import "../src/IHumanResources.sol";
import "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol"; // Mock for ChainLink
import "../test/MockERC20.sol"; // Assuming MockERC20 is used for USDC
import "../test/UniswapRouterMock.sol"; // Mock for Uniswap Router


contract HumanResourcesTest is Test {
    HumanResources public hrContract;
    MockERC20 public usdc;
    MockERC20 public weth;
    MockV3Aggregator public chainlinkOracle;
    UniswapRouterMock public uniswapRouter;

    address public hrManager = address(0x123);
    address public employee1 = address(0x456);
    address public employee2 = address(0x789);

    uint256 public weeklyUsdSalary = 5000 * 10 ** 18; // 5000 USD scaled to 18 decimals

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

        // Deploy HumanResources contract
        hrContract = new HumanResources();

        // Mint and fund tokens
        usdc.mint(hrManager, 100000 * 10 ** 6);  // Mint USDC for HR manager
        usdc.mint(employee1, 100000 * 10 ** 6);  // Mint USDC for employee1
    }

    function testRegisterEmployee() public {
        // Register an employee
        vm.prank(hrManager);
        vm.expectEmit(true, true, false, true);
        emit EmployeeRegistered(employee1, weeklyUsdSalary);
        hrContract.registerEmployee(employee1, weeklyUsdSalary);

        // Verify employee details
        (uint256 salary, uint256 employedSince, uint256 terminatedAt) = hrContract.getEmployeeInfo(employee1);
        assertEq(salary, weeklyUsdSalary, "Incorrect weekly salary");
        assertGt(employedSince, 0, "Employee not registered properly");
        assertEq(terminatedAt, 0, "Employee should not be terminated");
    }

    function testRegisterEmployeeUnauthorized() public {
        // Attempt to register an employee as a non-HR manager
        vm.prank(employee2);
        vm.expectRevert("NotAuthorized");
        hrContract.registerEmployee(employee1, weeklyUsdSalary);
    }

    function testTerminateEmployee() public {
        // Register and terminate an employee
        vm.prank(hrManager);
        hrContract.registerEmployee(employee1, weeklyUsdSalary);
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
        vm.expectRevert("NotAuthorized");
        hrContract.terminateEmployee(employee1);
    }

    function testWithdrawSalaryInUSDC() public {
        // Register employee and accrue salary
        vm.prank(hrManager);
        hrContract.registerEmployee(employee1, weeklyUsdSalary);

        // Advance time to simulate salary accrual
        vm.warp(block.timestamp + 7 days); // Advance 7 days

        // Employee withdraws salary
        vm.prank(employee1);
        vm.expectEmit(true, true, false, true);
        emit SalaryWithdrawn(employee1, false, weeklyUsdSalary / (10 ** 12)); // Adjust to 6 decimals
        hrContract.withdrawSalary();

        // Verify USDC balance
        assertEq(usdc.balanceOf(employee1), weeklyUsdSalary / (10 ** 12), "Incorrect USDC balance");
    }

    function testWithdrawSalaryInETH() public {
        // Register employee and switch to ETH
        vm.prank(hrManager);
        hrContract.registerEmployee(employee1, weeklyUsdSalary);

        vm.prank(employee1);
        hrContract.switchCurrency(); // Switch to ETH

        // Advance time to simulate salary accrual
        vm.warp(block.timestamp + 7 days); // Advance 7 days

        // Employee withdraws salary
        uint256 initialEthBalance = employee1.balance;
        vm.prank(employee1);
        vm.expectEmit(true, true, false, true);
        emit SalaryWithdrawn(employee1, true, 0); // Assuming mock returns 0
        hrContract.withdrawSalary();

        // Verify ETH balance (mock value for simplicity)
        uint256 ethBalanceAfter = employee1.balance;
        assertGt(ethBalanceAfter, initialEthBalance, "ETH balance should increase");
    }

    function testSwitchCurrency() public {
        // Register an employee
        vm.prank(hrManager);
        hrContract.registerEmployee(employee1, weeklyUsdSalary);

        // Switch currency to ETH
        vm.prank(employee1);
        vm.expectEmit(true, true, false, true);
        emit CurrencySwitched(employee1, true);
        hrContract.switchCurrency();

        // Verify currency preference
        (, , , , bool isEth) = hrContract.employees(employee1);
        assertTrue(isEth, "Employee should now prefer ETH");
    }

    function testSalaryAvailable() public {
        // Register employee and accrue salary
        vm.prank(hrManager);
        hrContract.registerEmployee(employee1, weeklyUsdSalary);

        // Advance time to simulate salary accrual
        vm.warp(block.timestamp + 7 days); // Advance 7 days

        // Verify available salary
        uint256 availableSalary = hrContract.salaryAvailable(employee1);
        assertEq(availableSalary, weeklyUsdSalary / (10 ** 12), "Incorrect available salary");
    }

    function testUnauthorizedWithdraw() public {
        // Attempt to withdraw salary as an unauthorized user
        vm.prank(employee2);
        vm.expectRevert("NotAuthorized");
        hrContract.withdrawSalary();
    }
}
