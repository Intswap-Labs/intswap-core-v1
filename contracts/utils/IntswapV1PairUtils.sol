// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "solmate/src/utils/FixedPointMathLib.sol";
import "../interfaces/IIntswapV1Pair.sol";


contract IntswapV1PairUtils {
    function getAvailablePriceRange(IIntswapV1Pair _pair) external view returns (uint256 availableMaxSqrtPrice, uint256 availableMinSqrtPrice) {
        uint256 currentSqrtPrice = _pair.currentSqrtPrice();
        uint256 maxSqrtPrice = _pair.maxSqrtPrice();
        uint256 minSqrtPrice = _pair.minSqrtPrice();
        uint256 nftRealReserve = _pair.nftRealReserve();

        uint256 a = FixedPointMathLib.divWadUp(maxSqrtPrice, currentSqrtPrice);
        uint256 b = FixedPointMathLib.divWadUp(currentSqrtPrice, minSqrtPrice);

        if (a < b) {
            (, availableMaxSqrtPrice) = _pair.getNewPriceRangeWithMinSqrtPrice(1);
            availableMinSqrtPrice = 1;
        } else {
            availableMaxSqrtPrice = type(uint256).max / currentSqrtPrice / nftRealReserve;
            (, availableMinSqrtPrice) = _pair.getNewPriceRangeWithMaxSqrtPrice(availableMaxSqrtPrice);
        }
    }
}