// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "solmate/src/utils/FixedPointMathLib.sol";
import "./interfaces/IIntswapV1Pair.sol";
import "./interfaces/IIntswapV1Factory.sol";

contract IntswapV1Pair is IIntswapV1Pair, ERC20, ReentrancyGuard, Initializable {
    enum RoundingDirection {
        Buy,
        Sell
    }
    
    IERC721 public nft;
    IERC20 constant public baseToken = IERC20(address(0x000000000000000000000000000000000000800A));
    IIntswapV1Factory public factory;
    
    uint256 public nftRealReserve;
    uint256 public baseTokenRealReserve;
    uint256 public maxSqrtPrice; 
    uint256 public minSqrtPrice; 
    uint256 public currentSqrtPrice;
    uint256 public liquidity;

    uint256 public blockTimestampLast;
    uint256 public sqrtPriceCumulativeLast;
    uint256 public lastMintFeeLiquidity;
    uint256 public constant MIN_LP_TOKEN = 1e3;
    
    event BuyNFT(
        uint256 nftAmountToBuy, 
        uint256 baseTokenInputAmount, 
        uint256 royaltyAmount, 
        uint256 newCurrentSqrtPrice
    );

    event SellNFT(
        uint256 nftAmountToSell, 
        uint256 baseTokenOutputAmount, 
        uint256 royaltyAmount, 
        uint256 newCurrentSqrtPrice
    );

    event AddLiquidity(
        uint256 nftInputAmount,
        uint256 baseTokenInputAmount,
        uint256 mintLPToken
    );

    event RemoveLiquidity(
        uint256 nftOutputAmount,
        uint256 baseTokenOutputAmount,
        uint256 burnLPToken
    );

    event MintFee(
        uint256 newLPToken
    );

    event NewPriceRange(
        uint256 newMaxSqrtPrice,
        uint256 newMinSqrtPrice,
        uint256 newLiquidity
    );

    event PruneOtherTokens(
        address token, 
        uint256 amount
    );
    event PruneOtherNFTs(
        address token, 
        uint256[] tokenIds
    );

    modifier onlyFactory() {
        require(msg.sender == address(factory), "IntswapV1Pair: Not Factory");
        _;
    }

    modifier isAllowed(bytes32 action) {
        require(factory.isAllowedToCall(address(this), msg.sender, action), "IntswapV1Pair: Only Allowed");
        _;
    }

    constructor(
        IERC721 _nft,
        IIntswapV1Factory _factory
    ) ERC20("Intswap V1", "Int-V1") {
        nft = _nft;
        blockTimestampLast = block.timestamp;
        factory = _factory;
    }

    function initializeWithSpecificNFTs(
        uint256[] memory _tokenIds, 
        uint256 _currentSqrtPrice,
        uint256 _maxSqrtPrice,
        uint256 _minSqrtPrice
    ) 
        external
        payable
        onlyFactory
        nonReentrant
        initializer
    {
        _sendSpecificNFTsToRecipient(msg.sender, address(this), _tokenIds);
        _internalInitialize(_tokenIds.length, _currentSqrtPrice, msg.sender, _maxSqrtPrice, _minSqrtPrice);
    }

    function buySpecificNFTs(
        uint256[] memory _tokenIds, 
        uint256 exceptedBaseTokenCostAmount
    ) 
        external
        payable 
        nonReentrant
        isAllowed(keccak256("buySpecificNFTs"))
    {
        _internalBuy(_tokenIds.length, exceptedBaseTokenCostAmount);
        _sendSpecificNFTsToRecipient(address(this), msg.sender, _tokenIds);
    }

    function sellSpecificNFTs(
        uint256[] memory _tokenIds, 
        uint256 exceptedBaseTokenReceivedAmount
    ) 
        external
        nonReentrant
        isAllowed(keccak256("sellSpecificNFTs"))
    {
        _sendSpecificNFTsToRecipient(msg.sender, address(this), _tokenIds);
        _internalSell(_tokenIds.length, exceptedBaseTokenReceivedAmount);
    }

    function addLiquidityWithSpecificNFT(
        uint256[] memory _tokenIds,
        uint256 expectedBaseTokenInputAmount
    ) 
        external
        payable
        nonReentrant
        isAllowed(keccak256("addLiquidityWithSpecificNFT"))
    {
        _sendSpecificNFTsToRecipient(msg.sender, address(this), _tokenIds);
        _internalAddLiquidity(_tokenIds.length, expectedBaseTokenInputAmount);
    }

    function removeliquidityForSpecificNFTs(
        uint256[] memory _tokenIds,
        uint256 expectedBaseTokenOutputAmount
    ) 
        external
        nonReentrant
        isAllowed(keccak256("removeliquidityForSpecificNFTs"))
    {
        _internalRemoveLiquidity(_tokenIds.length, expectedBaseTokenOutputAmount);
        _sendSpecificNFTsToRecipient(address(this), msg.sender, _tokenIds);
    }

    function removeAllForSpecificNFTs(
        RoundingDirection _flag, 
        uint256[] memory _exceptedTokenIds
    ) 
        external
        nonReentrant
        isAllowed(keccak256("removeAllForSpecificNFTs"))
    {
        uint256 nftReturnAmount = _internalRemoveAllLiquidity(_flag);

        if (_exceptedTokenIds.length > 0) {
            require(_exceptedTokenIds.length == nftReturnAmount, "IntswapV1Pair: Exceed expected amount");
        }

        _sendSpecificNFTsToRecipient(address(this), msg.sender, _exceptedTokenIds);
    }

    function updatePriceRangeWithMaxSqrtPrice(uint256 newMaxSqrtPrice) external onlyFactory nonReentrant {
        (uint256 newLiquidity, uint256 newMinSqrtPrice) = getNewPriceRangeWithMaxSqrtPrice(newMaxSqrtPrice);

        liquidity = newLiquidity;
        maxSqrtPrice = newMaxSqrtPrice;
        minSqrtPrice = newMinSqrtPrice;

        emit NewPriceRange(newMaxSqrtPrice, newMinSqrtPrice, newLiquidity);
    }

    function updatePriceRangeWithMinSqrtPrice(uint256 newMinSqrtPrice) external onlyFactory nonReentrant {
        (uint256 newLiquidity, uint256 newMaxSqrtPrice) = getNewPriceRangeWithMinSqrtPrice(newMinSqrtPrice);

        liquidity = newLiquidity;
        maxSqrtPrice = newMaxSqrtPrice;
        minSqrtPrice = newMinSqrtPrice;

        emit NewPriceRange(newMaxSqrtPrice, newMinSqrtPrice, newLiquidity);
    }

    function pruneOtherTokens(IERC20 _token, uint256 _amount) external onlyFactory {
        _token.transfer(msg.sender, _amount);

        emit PruneOtherTokens(address(_token), _amount);
    }

    function pruneOtherNFTs(IERC721 _token, uint256[] memory _tokenIds) external onlyFactory {
        require(_token != nft, "IntswapV1Pair: Not allow to prune reserve token");
        for (uint256 i; i < _tokenIds.length; i++) {
            _token.transferFrom(address(this), msg.sender, _tokenIds[i]);
        }

        emit PruneOtherNFTs(address(_token), _tokenIds);
    }

    function getInitLiquidityInfo(uint256 _nftAmount, uint256 _currentSqrtPrice) 
        public 
        view 
        returns (
            uint256 initLiquidity,
            uint256 deltaLPTokenAmount, 
            uint256 deltaBaseToken
        ) 
    {
        uint256 nftCalAmount = _nftAmount * FixedPointMathLib.WAD;
        
        uint256 numerator = FixedPointMathLib.mulWadDown(_currentSqrtPrice, maxSqrtPrice);
        
        uint256 denominator = maxSqrtPrice - _currentSqrtPrice;

        uint256 deltaRatio = FixedPointMathLib.divWadDown(numerator, denominator);

        initLiquidity = FixedPointMathLib.mulWadDown(nftCalAmount, deltaRatio);

        deltaBaseToken = FixedPointMathLib.mulWadDown(initLiquidity, _currentSqrtPrice - minSqrtPrice);

        deltaLPTokenAmount = (initLiquidity > MIN_LP_TOKEN) ? initLiquidity : MIN_LP_TOKEN;
    }

    function getBuyQuotoInfo(uint256 _nftAmount) 
        public 
        view 
        returns (
            uint256 baseTokenInputAmount, 
            uint256 tradingFee,
            uint256 royaltyAmount
        ) 
    {
        uint256 validFeeRatio = factory.getFeeRatio();
        (, uint256 validRoyaltyRatio) = factory.getRoyaltyInfo(address(this));
        uint256 validTradingRatio = FixedPointMathLib.WAD - validFeeRatio - validRoyaltyRatio;
        uint256 nftCalAmount = _nftAmount * FixedPointMathLib.WAD;

        uint256 baseTokenAmount;
        
        baseTokenAmount = _getInternalBuyQuotoInfo(nftCalAmount);
        
        tradingFee = FixedPointMathLib.mulDivUp(baseTokenAmount, validFeeRatio, validTradingRatio);
        royaltyAmount = FixedPointMathLib.mulDivUp(baseTokenAmount, validRoyaltyRatio, validTradingRatio);

        baseTokenInputAmount = baseTokenAmount + tradingFee + royaltyAmount;
    }

    function getSellQuotoInfo(uint256 _nftAmount) 
        public 
        view 
        returns (
            uint256 baseTokenOutputAmount, 
            uint256 tradingFee,
            uint256 royaltyAmount
        ) 
    {
        uint256 validFeeRatio = factory.getFeeRatio();
        (, uint256 validRoyaltyRatio) = factory.getRoyaltyInfo(address(this));
        uint256 validTradingRatio = FixedPointMathLib.WAD - validFeeRatio;
        uint256 nftCalAmount = FixedPointMathLib.mulWadDown(_nftAmount * FixedPointMathLib.WAD, validTradingRatio);

        uint256 baseTokenAmount;
        baseTokenAmount = _getInternalSellQuotoInfo(nftCalAmount);

        tradingFee = _nftAmount * FixedPointMathLib.WAD - nftCalAmount;
        royaltyAmount = FixedPointMathLib.mulWadDown(baseTokenAmount, validRoyaltyRatio);
        baseTokenOutputAmount = baseTokenAmount - royaltyAmount;
    }

    function getAddLiquidityInfo(uint256 _nftAmount) 
        public 
        view 
        returns (
            uint256 deltaLPTokenAmount, 
            uint256 deltaBaseToken
        ) 
    {
        uint256 nftCalAmount = _nftAmount * FixedPointMathLib.WAD;

        deltaBaseToken = FixedPointMathLib.mulDivUp(baseTokenRealReserve, nftCalAmount, nftRealReserve);

        deltaLPTokenAmount = FixedPointMathLib.mulDivDown(totalSupply(), nftCalAmount, nftRealReserve);
    }

    function getRemoveLiquidityInfo(uint256 _nftAmount) 
        public 
        view 
        returns (
            uint256 deltaLPTokenAmount, 
            uint256 deltaBaseToken
        ) 
    {
        uint256 nftCalAmount = _nftAmount * FixedPointMathLib.WAD;

        deltaBaseToken = FixedPointMathLib.mulDivDown(baseTokenRealReserve, nftCalAmount, nftRealReserve);

        deltaLPTokenAmount = FixedPointMathLib.mulDivUp(totalSupply(), nftCalAmount, nftRealReserve);
    }

    function getRemoveAllLiquidityInfo(RoundingDirection _flag, address _account) 
        public 
        view 
        returns (
            uint256 baseTokenReturnAmount, 
            uint256 nftReturnAmount, 
            uint256 baseTokenTradeAmount, 
            uint256 lpTokenBalance
        ) 
    {
        lpTokenBalance = balanceOf(_account);
        (uint256 nftValue, uint256 baseTokenValue) = getLPTokenValue(lpTokenBalance);

        uint256 nftFractionalPartForSelling = nftValue % FixedPointMathLib.WAD;
        uint256 nftFractionalPartForBuying = FixedPointMathLib.WAD - nftFractionalPartForSelling;
        if (nftFractionalPartForSelling > 0) {
            if (_flag == RoundingDirection.Buy) {
                baseTokenTradeAmount = _getInternalBuyQuotoInfo(nftFractionalPartForBuying);
                nftReturnAmount = nftValue / FixedPointMathLib.WAD + 1;
                baseTokenReturnAmount = baseTokenValue - baseTokenTradeAmount;
            } else {
                baseTokenTradeAmount = _getInternalSellQuotoInfo(nftFractionalPartForSelling);
                nftReturnAmount = nftValue / FixedPointMathLib.WAD;
                baseTokenReturnAmount = baseTokenValue + baseTokenTradeAmount;
            }
        } else {
            nftReturnAmount = nftValue / FixedPointMathLib.WAD;
            baseTokenReturnAmount = baseTokenValue;
        }
    }

    function getLPTokenValue(uint256 _amount) 
        public 
        view 
        returns (
            uint256 nftValue, 
            uint256 baseTokenValue
        ) 
    {
        nftValue = FixedPointMathLib.mulDivDown(nftRealReserve, _amount, totalSupply());
        baseTokenValue = FixedPointMathLib.mulDivDown(baseTokenRealReserve, _amount, totalSupply());
    }

    function getNewPriceRangeWithMaxSqrtPrice(uint256 newMaxSqrtPrice) 
        public 
        view 
        returns (
            uint256 newLiquidity, 
            uint256 newMinSqrtPrice
        ) 
    {
        uint256 numerator = FixedPointMathLib.mulWadDown(currentSqrtPrice, newMaxSqrtPrice);
        uint256 denominator = newMaxSqrtPrice - currentSqrtPrice;
        newLiquidity = FixedPointMathLib.mulDivDown(nftRealReserve, numerator, denominator);
        newMinSqrtPrice = currentSqrtPrice - FixedPointMathLib.divWadDown(baseTokenRealReserve, newLiquidity);
    }

    function getNewPriceRangeWithMinSqrtPrice(uint256 newMinSqrtPrice) 
        public 
        view 
        returns (
            uint256 newLiquidity, 
            uint256 newMaxSqrtPrice
        ) 
    {
        newLiquidity = FixedPointMathLib.divWadDown(baseTokenRealReserve, currentSqrtPrice - newMinSqrtPrice);
        newMaxSqrtPrice = currentSqrtPrice * newLiquidity / 
            (newLiquidity - FixedPointMathLib.mulWadDown(nftRealReserve, currentSqrtPrice));
    }

    function getTVLWithBaseToken() external view returns(uint256 tvl) {
        uint256 currentPrice = FixedPointMathLib.mulWadDown(currentSqrtPrice, currentSqrtPrice);
        tvl = baseTokenRealReserve + FixedPointMathLib.mulWadDown(nftRealReserve, currentPrice);
    }

    function _sendSpecificNFTsToRecipient(
        address nftSender,
        address nftRecipient,
        uint256[] memory nftIds
    ) internal {
        uint256 numNFTs = nftIds.length;
        for (uint256 i; i < numNFTs; ) {
            nft.transferFrom(nftSender, nftRecipient, nftIds[i]);

            unchecked {
                ++i;
            }
        }
    }

    function _internalBuy(uint256 _nftAmount, uint256 exceptedBaseTokenCostAmount) internal {
        require(nftRealReserve >= _nftAmount, "IntswapV1Pair: Transaction volume exceeds Reserve");

        (uint256 baseTokenInputAmount, , uint256 royaltyAmount) = getBuyQuotoInfo(_nftAmount);

        if (exceptedBaseTokenCostAmount > 0) {
            require(baseTokenInputAmount <= exceptedBaseTokenCostAmount, "IntswapV1Pair: Exceed expected spent amount");
        }
        
        (address royaltyVault, ) = factory.getRoyaltyInfo(address(this));

        require(baseTokenInputAmount <= msg.value, "IntswapV1Pair: Not enough ETH");
        
        uint256 deltaBaseTokenReserve = baseTokenInputAmount - royaltyAmount;
        
        baseTokenRealReserve += deltaBaseTokenReserve;
        nftRealReserve -= _nftAmount * FixedPointMathLib.WAD;

        _update();
        _mintFee();

        _safeTransferETH(royaltyVault, royaltyAmount);
        factory.addRoyalty(royaltyAmount);
        _safeTransferETH(msg.sender, msg.value - baseTokenInputAmount);

        bytes memory hookData = abi.encode(msg.sender, address(this), _nftAmount, baseTokenInputAmount, royaltyAmount, currentSqrtPrice);
        factory.hook(keccak256("Buy"), hookData);

        emit BuyNFT(_nftAmount, baseTokenInputAmount, royaltyAmount, currentSqrtPrice);
    }

    function _internalSell(uint256 _nftAmount, uint256 exceptedBaseTokenReceivedAmount) internal {
        (uint256 baseTokenOutputAmount, , uint256 royaltyAmount) = getSellQuotoInfo(_nftAmount);

        require(baseTokenRealReserve > baseTokenOutputAmount + royaltyAmount, 
            "IntswapV1Pair: Transaction volume exceeds Reserve");

        if (exceptedBaseTokenReceivedAmount > 0) {
            require(baseTokenOutputAmount >= exceptedBaseTokenReceivedAmount, 
            "IntswapV1Pair: Lower than expected amount");
        }
        
        uint256 deltaNFTReserve = _nftAmount * FixedPointMathLib.WAD;

        baseTokenRealReserve -= baseTokenOutputAmount + royaltyAmount;
        nftRealReserve += deltaNFTReserve;

        _update();

        _mintFee();

        (address royaltyVault, ) = factory.getRoyaltyInfo(address(this));

        _safeTransferETH(msg.sender, baseTokenOutputAmount);
        _safeTransferETH(royaltyVault, royaltyAmount);
        factory.addRoyalty(royaltyAmount);

        bytes memory hookData = abi.encode(msg.sender, address(this), _nftAmount, baseTokenOutputAmount, royaltyAmount, currentSqrtPrice);
        factory.hook(keccak256("Sell"), hookData);

        emit SellNFT(_nftAmount, baseTokenOutputAmount, royaltyAmount, currentSqrtPrice);
    }

    function _internalAddLiquidity(uint256 _nftAmount, uint256 expectedBaseTokenInputAmount) internal {
        (uint256 deltaLPTokenAmount, uint256 deltaBaseToken) = getAddLiquidityInfo(_nftAmount);
        if (expectedBaseTokenInputAmount > 0) {
            require(expectedBaseTokenInputAmount >= deltaBaseToken, "IntswapV1Pair: Exceed expected amount");
        }
        
        require(deltaBaseToken <= msg.value, "IntswapV1Pair: Not enough ETH");

        baseTokenRealReserve += deltaBaseToken;
        nftRealReserve += _nftAmount * FixedPointMathLib.WAD;

        _update();

        _mint(msg.sender, deltaLPTokenAmount);

        _safeTransferETH(msg.sender, msg.value - deltaBaseToken);

        bytes memory hookData = abi.encode(msg.sender, address(this), _nftAmount, deltaBaseToken, deltaLPTokenAmount);
        factory.hook(keccak256("Add"), hookData);

        emit AddLiquidity(
            _nftAmount,
            deltaBaseToken,
            deltaLPTokenAmount
        );
    }

    function _internalRemoveLiquidity(uint256 _nftAmount, uint256 expectedBaseTokenOutputAmount) internal {
        (uint256 deltaLPTokenAmount, uint256 deltaBaseToken) = getRemoveLiquidityInfo(_nftAmount);
        if (expectedBaseTokenOutputAmount > 0) {
            require(expectedBaseTokenOutputAmount <= deltaBaseToken, "IntswapV1Pair: Exceed expected amount");
        }
        require(deltaLPTokenAmount <= balanceOf(msg.sender), "IntswapV1Pair: Exceed LP Balance");

        _burn(msg.sender, deltaLPTokenAmount);

        baseTokenRealReserve -= deltaBaseToken;
        nftRealReserve -= _nftAmount * FixedPointMathLib.WAD;

        _update();
        
        _safeTransferETH(msg.sender, deltaBaseToken);

        bytes memory hookData = abi.encode(msg.sender, address(this), _nftAmount, deltaBaseToken, deltaLPTokenAmount);
        factory.hook(keccak256("Remove"), hookData);

        emit RemoveLiquidity(
            _nftAmount,
            deltaBaseToken,
            deltaLPTokenAmount
        );
    }

    function _internalRemoveAllLiquidity(RoundingDirection _flag) 
        internal 
        returns (
            uint256 nftReturnAmount
        )
    {
        uint256 baseTokenReturnAmount;
        uint256 baseTokenTradeAmount;
        uint256 lpTokenBalance;

        (baseTokenReturnAmount, nftReturnAmount, baseTokenTradeAmount, lpTokenBalance) = 
            getRemoveAllLiquidityInfo(_flag, msg.sender);

        _burn(msg.sender, lpTokenBalance);

        baseTokenRealReserve -= baseTokenReturnAmount;
        nftRealReserve -= nftReturnAmount * FixedPointMathLib.WAD;

        _update();

        _safeTransferETH(msg.sender, baseTokenReturnAmount);

        if (baseTokenTradeAmount > 0) {
            if (_flag == RoundingDirection.Buy) {
                emit BuyNFT(1, baseTokenTradeAmount, 0, currentSqrtPrice);
            } else {
                emit SellNFT(1, baseTokenTradeAmount, 0, currentSqrtPrice);
            }
        }

        bytes memory hookData = abi.encode(msg.sender, address(this), nftReturnAmount, baseTokenReturnAmount, lpTokenBalance);
        factory.hook(keccak256("Remove"), hookData);

        emit RemoveLiquidity(
            nftReturnAmount,
            baseTokenReturnAmount,
            lpTokenBalance
        );
    }

    function _internalInitialize(
        uint256 _nftAmount, 
        uint256 _currentSqrtPrice, 
        address _account,
        uint256 _maxSqrtPrice,
        uint256 _minSqrtPrice
    ) 
        internal
    {
        maxSqrtPrice = _maxSqrtPrice;
        minSqrtPrice = _minSqrtPrice;

        (, uint256 deltaLPTokenAmount, uint256 deltaBaseToken) = 
            getInitLiquidityInfo(_nftAmount, _currentSqrtPrice);
        
        require(deltaBaseToken <= msg.value, "IntswapV1Pair: Not enough ETH");

        baseTokenRealReserve += deltaBaseToken;
        nftRealReserve += _nftAmount * FixedPointMathLib.WAD;
        
        _update();

        _mint(_account, deltaLPTokenAmount);

        lastMintFeeLiquidity = liquidity;

        _safeTransferETH(tx.origin, msg.value - deltaBaseToken);

        emit AddLiquidity(
            _nftAmount,
            deltaBaseToken,
            deltaLPTokenAmount
        );
    }

    function _update() internal {
        if (baseTokenRealReserve != 0 && nftRealReserve != 0) {
            uint256 c = FixedPointMathLib.divWadUp(baseTokenRealReserve, nftRealReserve);
            uint256 minuend = FixedPointMathLib.divWadDown(c, maxSqrtPrice);
            uint256 b = (minuend > minSqrtPrice) ? minuend - minSqrtPrice : minSqrtPrice - minuend;
            uint256 sqrtRoot = FixedPointMathLib.sqrt((FixedPointMathLib.mulWadDown(b, b) + 4 * c) * FixedPointMathLib.WAD);
            
            currentSqrtPrice = (sqrtRoot + minSqrtPrice - minuend) / 2;
            liquidity = FixedPointMathLib.divWadDown(baseTokenRealReserve, currentSqrtPrice - minSqrtPrice);
        } else if (baseTokenRealReserve == 0 && nftRealReserve != 0) {
            currentSqrtPrice = minSqrtPrice;
            liquidity = FixedPointMathLib.mulWadDown(nftRealReserve, maxSqrtPrice * minSqrtPrice / (maxSqrtPrice - minSqrtPrice));
        } else if (baseTokenRealReserve != 0 && nftRealReserve ==0) {
            currentSqrtPrice = maxSqrtPrice;
            liquidity = FixedPointMathLib.divWadDown(baseTokenRealReserve, maxSqrtPrice - minSqrtPrice);
        } else {
            revert("IntswapV1Pair: Cal Error");
        }

        _updateOracle();
    }

    function _updateOracle() internal {
        uint256 blockTimestamp = block.timestamp;
        uint256 timeElapsed = blockTimestamp - blockTimestampLast;
        if (timeElapsed > 0) {
            sqrtPriceCumulativeLast += currentSqrtPrice * timeElapsed;
        }

        blockTimestampLast = blockTimestamp;
    }

    function _mintFee() internal {
        (address protocolFeeTo, uint256 protocolFeeRatio) = factory.getProtocolFeeInfo();
        if (protocolFeeTo != address(0) && protocolFeeRatio > 0 && liquidity > lastMintFeeLiquidity) {
            uint256 protocolFeeLiquidity = FixedPointMathLib.mulWadDown(
                liquidity - lastMintFeeLiquidity, protocolFeeRatio);

            uint256 deltaLPTokenAmount = FixedPointMathLib.mulDivDown(totalSupply(), protocolFeeLiquidity, liquidity);
            if (deltaLPTokenAmount > 0) {
                _mint(protocolFeeTo, deltaLPTokenAmount);
                lastMintFeeLiquidity = liquidity;
                
                emit MintFee(deltaLPTokenAmount);
            }
        }
    }

    function _safeTransferETH(address to, uint value) internal {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = to.call{value: value}("");

        require(success, "IntswapV1Pair: Transfer ETH Failed");
    }

    function _getInternalBuyQuotoInfo(uint256 _nftCalAmount) internal view returns (uint256) {
        uint256 newSqrtPrice = currentSqrtPrice * liquidity / 
            (liquidity - FixedPointMathLib.mulWadDown(_nftCalAmount, currentSqrtPrice));

        uint256 baseTokenAmount = FixedPointMathLib.mulWadUp(newSqrtPrice - currentSqrtPrice, liquidity);
        return baseTokenAmount;
    }

    function _getInternalSellQuotoInfo(uint256 _nftCalAmount) internal view returns (uint256) {
        uint256 newSqrtPrice = currentSqrtPrice * liquidity / 
            (FixedPointMathLib.mulWadUp(_nftCalAmount, currentSqrtPrice) + liquidity);

        uint256 baseTokenAmount = FixedPointMathLib.mulWadDown(currentSqrtPrice - newSqrtPrice, liquidity);
        return baseTokenAmount;
    }
}