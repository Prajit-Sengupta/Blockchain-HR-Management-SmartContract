// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract UniswapRouterMock{
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external pure returns (uint256[] memory amounts) {
        uint256[] memory result = new uint256[](path.length);
        result[0] = amountIn;
        result[1] = amountOutMin; // Simplified for testing purposes
        return result;
    }
}