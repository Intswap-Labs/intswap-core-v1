// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IIntswapV1Pair is IERC20 {
    function updatePriceRangeWithMaxSqrtPrice(uint256 newMaxSqrtPrice) external;
    function updatePriceRangeWithMinSqrtPrice(uint256 newMinSqrtPrice) external;
    // function updateRoyaltyInfo(uint256 _royaltyRatio) external;
    function pruneOtherTokens(IERC20 _token, uint256 _amount) external;
    function pruneOtherNFTs(IERC721 _token, uint256[] memory _tokenIds) external;
    function initializeWithSpecificNFTs(
        uint256[] memory _tokenIds, 
        uint256 _currentSqrtPrice,
        uint256 _maxSqrtPrice,
        uint256 _minSqrtPrice
    ) external payable;
    function nft() external returns (IERC721);
    function getInitLiquidityInfo(uint256 _nftAmount, uint256 _currentSqrtPrice) 
        external 
        view 
        returns (
            uint256 initLiquidity,
            uint256 deltaLPTokenAmount, 
            uint256 deltaBaseToken
        );
    function getTVLWithBaseToken() external view returns (uint256 tvl);
    function nftRealReserve() external view returns (uint256);
    function baseTokenRealReserve() external view returns (uint256);
    function currentSqrtPrice() external view returns (uint256);
    function maxSqrtPrice() external view returns (uint256);
    function minSqrtPrice() external view returns (uint256);
    function getNewPriceRangeWithMaxSqrtPrice(uint256 newMaxSqrtPrice) 
        external
        view 
        returns (
            uint256 newLiquidity, 
            uint256 newMinSqrtPrice
        );
    function getNewPriceRangeWithMinSqrtPrice(uint256 newMinSqrtPrice) 
        external 
        view 
        returns (
            uint256 newLiquidity, 
            uint256 newMaxSqrtPrice
        );
}