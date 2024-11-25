// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    uint8 private _decimals;

    // Constructor to initialize the token with name, symbol, and decimals
    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;  // Set the decimals to the provided value
    }

    // Override the decimals function to return the configured decimals
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    // Mint new tokens
    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    // Burn tokens from an account
    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }
}
