// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IIntswapV1RoyaltyVault {
    function deposit(address pair, uint256 amount) external;
    function withdraw(address to, uint256 amount) external;
}