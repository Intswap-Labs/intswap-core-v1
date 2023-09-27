// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IIntswapV1IncentiveStrategy {
    function updatePosition(address _lpToken, address account) external;
    function getReward(address _lpToken, address _account) external returns (address, uint256);
    function earned(address _lpToken, address _account) external view returns (IERC20, uint256);
    function name() external view returns (string memory);
    function estimatedOneYearRewards(address _lpToken) external view returns (IERC20, uint256);
}