// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import "./interfaces/IIntswapV1Factory.sol";
import "./interfaces/IIntswapV1Pair.sol";
import "./interfaces/IIntswapV1RoyaltyVault.sol";
import "./interfaces/IIntswapV1TimelockController.sol";
import "./interfaces/IIntswapV1ERC721Owner.sol";

contract IntswapV1CreatorManager is Ownable {
    enum ApplicationStatus {
        Pending,
        Complete,
        Cancel
    }

    struct NewApplication {
        address to;
        bytes data;
        uint256 nonce;
        ApplicationStatus status;
    }

    IIntswapV1Factory public factory;
    address public royaltyVault;
    IIntswapV1TimelockController public timelockController;
    uint256 public delay = 1 days;
    uint256 public nonce;
    
    mapping(bytes32 => NewApplication) public newApplications;
    mapping(address => address) public officialNFTOwner;

    event NewFactory(address oldFactory, address newFactory);
    event NewTimelockController(address oldTimelockController, address newTimelockController);
    event NewOfficialNFTOwner(address nft, address newOwner);
    
    event NewApplyUpdatingPriceRangeWithMaxSqrtPrice(
        bytes32 id,
        address pair,
        uint256 newMaxSqrtPrice,
        uint256 startTime,
        uint256 delay,
        string title,
        string desc
    );

    event NewApplyUpdatingPriceRangeWithMinSqrtPrice(
        bytes32 id,
        address pair,
        uint256 newMinSqrtPrice,
        uint256 startTime,
        uint256 delay,
        string title,
        string desc
    );

    event NewApplyUpdatingRoyaltyInfo(
        bytes32 id,
        address pair,
        uint256 newRoyaltyRatio,
        uint256 startTime,
        uint256 delay,
        string title,
        string desc
    );

    event NewApplyWithdrawRoyalty(
        bytes32 id,
        address pair,
        address to,
        uint256 newRoyaltyRatio,
        uint256 startTime,
        uint256 delay,
        string title,
        string desc 
    );

    event NewApplyUpdatingRoyaltyRewardRatio(
        bytes32 id,
        address pair,
        uint256 newRoyaltyRewardRatio,
        uint256 startTime,
        uint256 delay,
        string title,
        string desc
    );

    event ExecuteApplication(bytes32 _id);

    event NewDelay(uint256 oldDelay, uint256 newDelay);
    
    constructor(address _royaltyVault, IIntswapV1TimelockController _timelockController) {
        royaltyVault = _royaltyVault;
        timelockController = _timelockController;
    }

    function updateFactory(IIntswapV1Factory _factory) external onlyOwner {
        address oldFactory = address(factory);
        factory = _factory;

        emit NewFactory(oldFactory, address(_factory));
    }

    function updateTimelockController(IIntswapV1TimelockController _timelockController) external onlyOwner {
        address oldTimelockController = address(timelockController);
        timelockController = _timelockController;

        emit NewTimelockController(oldTimelockController, address(_timelockController));
    }

    function applyUpdatingPriceRangeWithMaxSqrtPrice(
        address _pair,
        uint256 _newMaxSqrtPrice,
        string memory _title,
        string memory _desc
    )
        external 
    {
        require(factory.isOfficialPair(_pair), "CreatorManager: Not Official Pair");

        address _nft = address(IIntswapV1Pair(_pair).nft());
        require(isNFTOwner(_nft, msg.sender), "CreatorManager: Not Owner");

        bytes memory data = abi.encodeWithSignature(
            "updatePriceRangeWithMaxSqrtPrice(address,uint256)",
            _pair,
            _newMaxSqrtPrice
        );

        bytes32 id = _apply(address(factory), data);

        emit NewApplyUpdatingPriceRangeWithMaxSqrtPrice(
            id,
            _pair,
            _newMaxSqrtPrice,
            block.timestamp,
            delay,
            _title,
            _desc
        );
    }

    function applyUpdatingPriceRangeWithMinSqrtPrice(
        address _pair, 
        uint256 _newMinSqrtPrice,
        string memory _title,
        string memory _desc
    ) 
        external 
    {
        require(factory.isOfficialPair(_pair), "CreatorManager: Not Official Pair");

        address _nft = address(IIntswapV1Pair(_pair).nft());
        require(isNFTOwner(_nft, msg.sender), "CreatorManager: Not Owner");

        bytes memory data = abi.encodeWithSignature(
            "updatePriceRangeWithMinSqrtPrice(address,uint256)",
            _pair,
            _newMinSqrtPrice
        );

        bytes32 id = _apply(address(factory), data);

        emit NewApplyUpdatingPriceRangeWithMaxSqrtPrice(
            id,
            _pair,
            _newMinSqrtPrice,
            block.timestamp,
            delay,
            _title,
            _desc
        );
    }

    function applyUpdatingRoyaltyInfo(
        address _pair, 
        uint256 _royaltyRatio,
        string memory _title,
        string memory _desc
    ) 
        external 
    {
        require(factory.isOfficialPair(_pair), "CreatorManager: Not Official Pair");

        address _nft = address(IIntswapV1Pair(_pair).nft());
        require(isNFTOwner(_nft, msg.sender), "CreatorManager: Not Owner");

        bytes memory data = abi.encodeWithSignature(
            "updateCustomizeRoyaltyInfo(address,uint256)",
            _pair,
            _royaltyRatio
        );

        bytes32 id = _apply(address(factory), data);

        emit NewApplyUpdatingRoyaltyInfo(
            id,
            _pair,
            _royaltyRatio,
            block.timestamp,
            delay,
            _title,
            _desc
        );
    }

    function applyWithdrawRoyalty(
        address _pair,
        uint256 _amount,
        string memory _title,
        string memory _desc
    ) 
        external 
    {
        require(factory.isOfficialPair(_pair), "CreatorManager: Not Official Pair");

        address _nft = address(IIntswapV1Pair(_pair).nft());
        require(isNFTOwner(_nft, msg.sender), "CreatorManager: Not Owner");

        bytes memory data = abi.encodeWithSignature(
            "withdraw(address,address,uint256)",
            _pair,
            msg.sender,
            _amount
        );

        bytes32 id = _apply(royaltyVault, data);

        emit NewApplyWithdrawRoyalty(
            id,
            _pair,
            msg.sender,
            _amount,
            block.timestamp,
            delay,
            _title,
            _desc
        );
    }

    function applyUpdateRoyaltyRewardRatio(
        address _pair,
        uint256 _rewardRatio,
        string memory _title,
        string memory _desc
    ) 
        external 
    {
        require(factory.isOfficialPair(_pair), "CreatorManager: Not Official Pair");

        address _nft = address(IIntswapV1Pair(_pair).nft());
        require(isNFTOwner(_nft, msg.sender), "CreatorManager: Not Owner");

        bytes memory data = abi.encodeWithSignature(
            "updateRewardRatio(address,uint256)",
            _pair,
            _rewardRatio
        );

        bytes32 id = _apply(royaltyVault, data);

        emit NewApplyUpdatingRoyaltyRewardRatio(
            id,
            _pair,
            _rewardRatio,
            block.timestamp,
            delay,
            _title,
            _desc
        );
    }

    function executeApplication(bytes32 _id) external {
        NewApplication storage newApplication = newApplications[_id];
        require(newApplication.status != ApplicationStatus.Complete, "CreatorManager: Already Complete");

        timelockController.execute(
            newApplication.to,
            0,
            newApplication.data,
            bytes32(0),
            bytes32(newApplication.nonce)
        );

        newApplication.status = ApplicationStatus.Complete;

        emit ExecuteApplication(_id);
    }

    function addOfficialNFTOwner(address _nft, address _account) external onlyOwner {
        require(_account != address(0), "IntswapV1CreatorManager: Not Zero");
        try IIntswapV1ERC721Owner(_nft).owner() {
            revert("IntswapV1CreatorManager: Support Owner()");
        } catch {
            officialNFTOwner[_nft] = _account;
            emit NewOfficialNFTOwner(_nft, _account);
        }
    }

    function updateDelay(uint256 _delay) external onlyOwner {
        require(_delay != 0, "IntswapV1CreatorManager: Not Zero");
        uint256 oldDelay = delay;
        delay = _delay;
        
        emit NewDelay(oldDelay, _delay);
    }

    function isNFTOwner(address _nft, address _account) public view returns (bool isOwner) {
        try IIntswapV1ERC721Owner(_nft).owner() returns (address nftOwner) {
            if (nftOwner == _account) {
                isOwner = true;
            }
        } catch {
            if (officialNFTOwner[_nft] == _account) {
                isOwner = true;
            }
        }
    }

    function getNFTOwner(address _nft, address _account) public view returns (bool isOwner) {
        try IIntswapV1ERC721Owner(_nft).owner() returns (address nftOwner) {
            if (nftOwner == _account) {
                isOwner = true;
            }
        } catch {
            if (officialNFTOwner[_nft] == _account) { 
                isOwner = true;
            }
        }
    }

    function _apply(address _to, bytes memory _data) internal returns (bytes32) {
        bytes32 id = timelockController.hashOperation(
            address(_to),
            0,
            _data,
            bytes32(0),
            bytes32(nonce)
        );

        NewApplication storage newApplication = newApplications[id];
        newApplication.to = _to;
        newApplication.data = _data;
        newApplication.status = ApplicationStatus.Pending;
        newApplication.nonce = nonce;

        timelockController.schedule(
            _to,
            0,
            _data,
            bytes32(0),
            bytes32(nonce),
            delay
        );

        nonce += 1;
        return id;
    }
}
