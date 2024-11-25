// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {HumanResources} from "../src/HumanResources.sol";

contract HumanResourcesScript is Script {
    // Declare an instance of the HumanResources contract
    HumanResources public humanResources;

    // Set up function for any initializations (if needed)
    function setUp() public {}

    // Run function for deploying the HumanResources contract
    function run() public {
        // Start the broadcast (for deployment)
        vm.startBroadcast();

        // Deploy the HumanResources contract (assuming the constructor requires an HR manager address)
        address hrManagerAddress = msg.sender;  // Replace with a valid address
        humanResources = new HumanResources(hrManagerAddress);

        // Stop broadcasting
        vm.stopBroadcast();

        // Optional: Log the contract address
        console.log("HumanResources contract deployed at:", address(humanResources));
    }
}
