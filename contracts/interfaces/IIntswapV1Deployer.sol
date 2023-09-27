// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IIntswapV1Deployer {
    function deploy(
        address _nft,
        address _baseToken,
        uint256 _defaultMaxSqrtPrice, 
        uint256 _defaultMinSqrtPrice,
        uint256 _royaltyRatio
    ) external returns (address newPair);
}