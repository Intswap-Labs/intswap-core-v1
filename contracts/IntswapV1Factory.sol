// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "./interfaces/IIntswapV1Factory.sol";
import "./interfaces/IIntswapV1Pair.sol";
import "./interfaces/IIntswapV1RoyaltyVault.sol";
import "./interfaces/IIncentiveHook.sol";
import "./interfaces/IIntswapV1Permision.sol";
import "./IntswapV1Pair.sol";

contract IntswapV1Factory is IIntswapV1Factory, Ownable {
    bytes4 private constant INTERFACE_ID_ERC2981 = 
        type(IERC2981).interfaceId;

    struct RoyaltyInfo {
        uint256 officialRoyaltyRatio;
        uint256 customizeRoyaltyRatio;
        bool isOfficialValid;
    }

    IIntswapV1RoyaltyVault public royaltyVault;
    IIntswapV1Permision public intswapV1Permision;
    address public timelockController;
    address public protocolFeeTo;
    uint256 public globalRoyaltyRatio;
    uint256 public defaultMaxSqrtPriceMultiple = 3e18; 
    uint256 public defaultMinSqrtPriceMultiple = 0.33e18; 
    uint256 public protocolFeeRatio = 0.1e18;
    uint256 public feeRatio = 0.003e18;
    uint256 private constant DEFAULT_TOKEN_ID = 0;
    uint256 private constant DEFAULT_SALES_PRICE = 1e18;
    uint256 public constant MIN_LP_TOKEN = 1e3;

    bool public isGlobalRoyaltyRatioValid;
    mapping(address => address) public getPair;
    mapping(address => RoyaltyInfo) public royaltyRatios;
    mapping(address => bool) public isOfficialPair;
    address[] public allPairs;

    IIncentiveHook public incentiveHook;

    event NewPair(address nft, address pair);
    event AddRoyalty(address pair, uint256 amount);
    event NewPriceRangeMultiple(uint256 maxMultiple, uint256 minMultiple);
    event NewGlobalRoyaltyRatio(uint256 newValue, bool status);
    event NewOfficialRoyaltyRatio(address pair, uint256 newValue, bool status);
    event NewCustomizeRoyaltyInfo(address pair, uint256 newRoyaltyInfo);
    event NewIncentiveHook(address oldAddr, address newAddr);
    event NewPermision(address oldAddr, address newAddr);
    event NewPriceRangeWithMaxSqrtPrice(address pair, uint256 newMaxSqrtPrice);
    event NewPriceRangeWithMinSqrtPrice(address pair, uint256 newMinSqrtPrice);
    event PruneOtherTokens(address pair, address token, uint256 amount);
    event PruneOtherNFTs(address pair, address token, uint256[] tokenIds);

    modifier onlyTimelockController() {
        require(msg.sender == timelockController, "IntswapV1Factory: Only TimelockController");
        _;
    }

    modifier isAllowed(bytes32 action) {
        require(isAllowedToCall(address(this), msg.sender, action), "IntswapV1Factory: Only Allowed");
        _;
    }

    constructor(
        IIntswapV1RoyaltyVault _royaltyVault,
        IIntswapV1Permision _intswapV1Permision,
        address _timelockController
    ) {
        royaltyVault = _royaltyVault;
        intswapV1Permision = _intswapV1Permision;
        timelockController = _timelockController;
        protocolFeeTo = msg.sender;
    }

    function createPairAndInitialize(
        address _nft,
        uint256[] memory _tokenIds, 
        uint256 _currentSqrtPrice
    ) 
        external
        payable
        isAllowed(keccak256("createPairAndInitialize"))
        returns (
            address newPair
        ) 
    {
        newPair = _createPair(_nft);

        _initializeNewPair(
            IERC721(_nft), 
            IIntswapV1Pair(newPair), 
            _tokenIds, 
            _currentSqrtPrice
        );
    }

    function hook(bytes32 action, bytes memory data) external {
        require(isOfficialPair[msg.sender], "IntswapV1Factory: Not Official Pair");
        if (address(incentiveHook) != address(0)) {
            incentiveHook.hook(action, data);
        }
    }

    function updateMarketMakerPriceRangeMultiple(
        uint256 _defaultMaxSqrtPriceMultiple, 
        uint256 _defaultMinSqrtPriceMultiple
    ) 
        external 
        onlyOwner 
    {
        defaultMaxSqrtPriceMultiple = _defaultMaxSqrtPriceMultiple;
        defaultMinSqrtPriceMultiple = _defaultMinSqrtPriceMultiple;
        emit NewPriceRangeMultiple(defaultMaxSqrtPriceMultiple, defaultMinSqrtPriceMultiple);
    }

    function updateGlobalRoyaltyRatio(
        uint256 _globalRoyaltyRatio, 
        bool _status
    ) 
        external 
        onlyOwner 
    {
        globalRoyaltyRatio = _globalRoyaltyRatio;
        isGlobalRoyaltyRatioValid = _status;

        emit NewGlobalRoyaltyRatio(_globalRoyaltyRatio, _status);
    }

    function updateOfficialRoyaltyRatio(
        address _pair, 
        uint256 _officialRoyaltyRatio, 
        bool _status
    ) 
        external 
        onlyOwner 
    {
        RoyaltyInfo storage royaltyRatio = royaltyRatios[_pair];
        royaltyRatio.officialRoyaltyRatio = _officialRoyaltyRatio;
        royaltyRatio.isOfficialValid = _status;
        emit NewOfficialRoyaltyRatio(_pair, _officialRoyaltyRatio, _status);
    }

    function updateCustomizeRoyaltyInfo(
        address _pair, 
        uint256 _royaltyRatio
    ) 
        external 
        onlyTimelockController 
    {
        RoyaltyInfo storage royaltyRatio = royaltyRatios[_pair];
        royaltyRatio.customizeRoyaltyRatio = _royaltyRatio;

        emit NewCustomizeRoyaltyInfo(_pair, _royaltyRatio);
    }

    function updateIncentiveHook(
        IIncentiveHook _incentiveHook
    ) 
        external 
        onlyOwner 
    {
        address oldIncentiveHook = address(incentiveHook);
        incentiveHook = _incentiveHook;

        emit NewIncentiveHook(oldIncentiveHook, address(incentiveHook));
    }

    function updatePermision(
        IIntswapV1Permision _intswapV1Permision
    ) 
        external 
        onlyOwner 
    {
        address oldPermision = address(intswapV1Permision);
        intswapV1Permision = _intswapV1Permision;

        emit NewPermision(oldPermision, address(intswapV1Permision));
    }


    function addRoyalty(uint256 _amount) external {
        require(isOfficialPair[msg.sender], "IntswapV1Factory: Not Official Pair");
        royaltyVault.deposit(msg.sender, _amount);

        emit AddRoyalty(msg.sender, _amount);
    } 

    function updatePriceRangeWithMaxSqrtPrice(
        IIntswapV1Pair _pair, 
        uint256 _newMaxSqrtPrice
    )
        external 
        onlyTimelockController 
    {
        _pair.updatePriceRangeWithMaxSqrtPrice(_newMaxSqrtPrice);
        emit NewPriceRangeWithMaxSqrtPrice(address(_pair), _newMaxSqrtPrice);
    }

    function updatePriceRangeWithMinSqrtPrice(
        IIntswapV1Pair _pair, 
        uint256 _newMinSqrtPrice
    ) 
        external 
        onlyTimelockController 
    {
        _pair.updatePriceRangeWithMinSqrtPrice(_newMinSqrtPrice);
        emit NewPriceRangeWithMinSqrtPrice(address(_pair), _newMinSqrtPrice);
    }

    function pruneOtherTokens(
        IIntswapV1Pair _pair, 
        IERC20 _token, 
        uint256 _amount
    ) 
        external 
        onlyOwner 
    {
        _pair.pruneOtherTokens(_token, _amount);
        emit PruneOtherTokens(address(_pair), address(_token), _amount);
    }

    function pruneOtherNFTs(
        IIntswapV1Pair _pair, 
        IERC721 _token, 
        uint256[] memory _tokenIds
    ) 
        external 
        onlyOwner 
    {
        _pair.pruneOtherNFTs(_token, _tokenIds);
        emit PruneOtherNFTs(address(_pair), address(_token), _tokenIds);
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function getProtocolFeeInfo() external view returns (address, uint256) {
        return (protocolFeeTo, protocolFeeRatio);
    }

    function getFeeRatio() external view returns (uint256) {
        return feeRatio;
    }

    function getRoyaltyInfo(address _pair) external view returns (address, uint256) {
        RoyaltyInfo storage royaltyRatio = royaltyRatios[_pair];

        uint256 finalRoyaltyRatio;
        if (royaltyRatio.isOfficialValid) {
            finalRoyaltyRatio = royaltyRatio.officialRoyaltyRatio;
        } else if (isGlobalRoyaltyRatioValid) {
            finalRoyaltyRatio = globalRoyaltyRatio;
        } else {
            finalRoyaltyRatio = royaltyRatio.customizeRoyaltyRatio;
        }

        return (address(royaltyVault), finalRoyaltyRatio);
    }

    function getDefaultInitLiquidityInfo(uint256 _nftAmount, uint256 _currentSqrtPrice) 
        public 
        view 
        returns (
            uint256 initLiquidity,
            uint256 deltaLPTokenAmount, 
            uint256 deltaBaseToken,
            uint256 defaultMaxSqrtPrice,
            uint256 defaultMinSqrtPrice
        ) 
    {
        defaultMaxSqrtPrice = FixedPointMathLib.mulWadUp(_currentSqrtPrice, defaultMaxSqrtPriceMultiple);

        defaultMinSqrtPrice = FixedPointMathLib.mulWadDown(_currentSqrtPrice, defaultMinSqrtPriceMultiple);

        uint256 nftCalAmount = _nftAmount * FixedPointMathLib.WAD;
        
        uint256 numerator = FixedPointMathLib.mulWadDown(_currentSqrtPrice, defaultMaxSqrtPrice);
        
        uint256 denominator = defaultMaxSqrtPrice - _currentSqrtPrice;

        uint256 deltaRatio = FixedPointMathLib.divWadDown(numerator, denominator);

        initLiquidity = FixedPointMathLib.mulWadDown(nftCalAmount, deltaRatio);

        deltaBaseToken = FixedPointMathLib.mulWadDown(initLiquidity, _currentSqrtPrice - defaultMinSqrtPrice);

        deltaLPTokenAmount = (initLiquidity > MIN_LP_TOKEN) ? initLiquidity : MIN_LP_TOKEN;
    }

    function getTotalTVLWithBaseToken() external view returns(uint256 totalTVL) {
        for (uint256 i; i < allPairs.length; i++) {
            uint256 tvl = IIntswapV1Pair(allPairs[i]).getTVLWithBaseToken();
            totalTVL += tvl;
        }
    }

    function isAllowedToCall(address called, address caller, bytes32 action) public view returns(bool) {
        return intswapV1Permision.isAllowedToCall(called, caller, action);
    }

    function _createPair(address _nft) internal returns (address newPair) {
        require(_nft != address(0), "IntswapV1Factory: Not Allow address(0)");
        require(getPair[_nft] == address(0), "IntswapV1Factory: Already exists");

        uint256 customizeRoyaltyRatio = _getDefaultRoyaltyRatio(_nft);

        newPair = address(
            new IntswapV1Pair(
                IERC721(_nft),
                IIntswapV1Factory(address(this))
            )
        );

        RoyaltyInfo storage royaltyRatio = royaltyRatios[newPair];
        royaltyRatio.customizeRoyaltyRatio = customizeRoyaltyRatio;
        getPair[_nft] = newPair;
        isOfficialPair[newPair] = true;
        allPairs.push(newPair);
        
        emit NewPair(_nft, newPair);
    }

    function _initializeNewPair(
        IERC721 _nft,
        IIntswapV1Pair _newPair,
        uint256[] memory _tokenIds, 
        uint256 _currentSqrtPrice
    ) 
        internal 
    {

        _nft.setApprovalForAll(address(_newPair), true);

        (, , , uint256 defaultMaxSqrtPrice, uint256 defaultMinSqrtPrice) = 
            getDefaultInitLiquidityInfo(_tokenIds.length, _currentSqrtPrice);

        _sendSpecificNFTsToRecipient(address(_nft), msg.sender, address(this), _tokenIds);
        
        _newPair.initializeWithSpecificNFTs{value: msg.value}(_tokenIds, _currentSqrtPrice, defaultMaxSqrtPrice, defaultMinSqrtPrice);
        uint256 mintLPTokenAmount = _newPair.balanceOf(address(this));
        _newPair.transfer(msg.sender, mintLPTokenAmount);
    }

    function _sendSpecificNFTsToRecipient(
        address nft,
        address nftSender,
        address nftRecipient,
        uint256[] memory nftIds
    ) internal {
        uint256 numNFTs = nftIds.length;
        for (uint256 i; i < numNFTs; ) {
            IERC721(nft).transferFrom(nftSender, nftRecipient, nftIds[i]);

            unchecked {
                ++i;
            }
        }
    }

    function _getDefaultRoyaltyRatio(address _nft) internal view returns (uint256 royaltyRatio) {
        try IERC2981(_nft).supportsInterface(INTERFACE_ID_ERC2981) returns (bool isSupportERC2981) {
            if (isSupportERC2981) {
                (, royaltyRatio) = IERC2981(_nft).royaltyInfo(
                    DEFAULT_TOKEN_ID,
                    DEFAULT_SALES_PRICE
                );
            }
        } catch {
        }
    }
}
