// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {HumanResources} from "../src/HumanResources.sol";

contract HumanResourcesScript is Script {
    HumanResources public humanResources;
    function setUp() public {}

    // Function for deploying the HumanResources contract
    function run() public {
        // Start the broadcast
        vm.startBroadcast();

        humanResources = new HumanResources();

        vm.stopBroadcast();

        console.log("HumanResources contract deployed at:", address(humanResources));
    }
}
