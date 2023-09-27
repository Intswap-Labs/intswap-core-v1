// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "solmate/src/utils/FixedPointMathLib.sol";
import "./interfaces/IIntswapV1Factory.sol";
import "./interfaces/IIntswapV1Pair.sol";
import "./interfaces/IIntswapV1ERC721Owner.sol";
import "./interfaces/IRoyaltyDistributionStrategy.sol";

contract IntswapV1RoyaltyVault is Ownable {
    using SafeERC20 for IERC20;

    IIntswapV1Factory public factory;
    IRoyaltyDistributionStrategy public rewardStrategy;
    address public immutable timelockController;

    uint256 public globalRewardRatio;

    mapping(address => uint256) public claimRecords;
    mapping(address => uint256) public rewardRatios;

    event NewRewardStrategy(address oldRewardStrategy, address newRewardStrategy);
    event NewGlobalRewardRatio(uint256 oldRewardRatio, uint256 newRewardRatio);
    event NewRewardRatio(address pair, uint256 newRewardRatio);

    event NewFactory(address oldFactory, address newFactory);
    event NewDeposit(address pair, uint256 amount);
    event NewWithdraw(address pair, address to, uint256 amount);
    event NewRewardDistribute(address pair, uint256 amount);

    modifier onlyFactory() {
        require(msg.sender == address(factory), "IntswapV1RoyaltyVault: Not Factory");
        _;
    }

    modifier onlyTimelockController() {
        require(msg.sender == timelockController, "IntswapV1RoyaltyVault: Only TimelockController");
        _;
    }

    constructor(
        address _timelockController
    ) {
        timelockController = _timelockController;
    }

    receive() external payable {}

    function updateRewardStrategy(IRoyaltyDistributionStrategy _rewardStrategy) external onlyOwner {
        address oldRewardStrategy = address(rewardStrategy);
        rewardStrategy = _rewardStrategy;

        emit NewRewardStrategy(oldRewardStrategy, address(_rewardStrategy));
    }

    function updateGlobalRewardRatio(uint256 _globalRewardRatio) external onlyOwner {
        uint256 oldGlobalRewardRatio = globalRewardRatio;
        globalRewardRatio = _globalRewardRatio;

        emit NewGlobalRewardRatio(oldGlobalRewardRatio, _globalRewardRatio);
    }
    
    function updateFactory(IIntswapV1Factory _factory) external onlyOwner {
        address oldFactory = address(factory);
        factory = _factory;

        emit NewFactory(oldFactory, address(_factory));
    }
    
    function updateRewardRatio(address _pair, uint256 _rewardRatio) external onlyTimelockController {
        rewardRatios[_pair] = _rewardRatio;

        emit NewRewardRatio(_pair, _rewardRatio);
    }
    
    function deposit(address _pair, uint256 _amount) external onlyFactory {
        uint256 claimedAmount = _amount;
        if (address(rewardStrategy) != address(0)) {
            uint256 rewardRatio = getRoyaltyRewardRatio(_pair);
            if (rewardRatio > 0) {
                uint256 rewardAmount = FixedPointMathLib.mulWadDown(_amount, rewardRatio);
                claimedAmount = _amount - rewardAmount;

                _safeTransferETH(address(rewardStrategy), rewardAmount);
                rewardStrategy.distribute(_pair, rewardAmount);
                emit NewRewardDistribute(_pair, rewardAmount);
            } 
        }

        claimRecords[_pair] += claimedAmount;
        emit NewDeposit(_pair, claimedAmount);
    }

    function withdraw(IIntswapV1Pair _pair, address _to, uint256 _amount) external onlyTimelockController {
        require(factory.isOfficialPair(address(_pair)), "IntswapV1RoyaltyVault: Not Official Pair");

        claimRecords[address(_pair)] -= _amount;
        _safeTransferETH(_to, _amount);

        emit NewWithdraw(address(_pair), _to, _amount);
    }

    function getRoyaltyRewardRatio(address _pair) public view returns (uint256) {
        return (globalRewardRatio > rewardRatios[_pair]) ? globalRewardRatio : rewardRatios[_pair];
    }

    function _safeTransferETH(address to, uint value) internal {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = to.call{value: value}("");

        require(success, "IntswapV1RoyaltyVault: Transfer ETH Failed");
    }
}
