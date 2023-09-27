// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IIntswapV1StakingCenter {
    function totalStakingAmount(IERC20 _lpToken) external view returns (uint256);
    function balanceOf(IERC20 _lpToken, address _account) external view returns (uint256);
}