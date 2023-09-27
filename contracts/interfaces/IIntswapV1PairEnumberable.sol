// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./IIntswapV1Pair.sol";

interface IIntswapV1PairEnumberable is IIntswapV1Pair {
    function initializeWithAnyNFTs(
        uint256 _nftAmount, 
        uint256 _currentSqrtPrice
    ) external;
}