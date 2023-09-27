// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./IIntswapV1IncentiveStrategy.sol";

interface IRoyaltyDistributionStrategy is IIntswapV1IncentiveStrategy {
    function distribute(address pair, uint256 amount) external;
}