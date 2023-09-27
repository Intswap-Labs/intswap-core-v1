// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IIntswapV1Factory.sol";
import "./interfaces/IIntswapV1IncentiveStrategy.sol";

contract IntswapV1StakingCenter is Ownable, ReentrancyGuard {
    struct LPStakingPool {
        uint256 totalStakingAmount;
        mapping(address => uint256) userStakings;
        IncentiveStrategy[] incentiveStrategies;
    }

    struct IncentiveStrategy {
        IIntswapV1IncentiveStrategy strategy;
        bool isActive;
    }

    IIntswapV1Factory public factory;
    IncentiveStrategy[] public globalIncentiveStrategies;
    mapping(IERC20 => LPStakingPool) public stakingPools;

    event Stake(address account, address lpToken, uint256 amount);
    event Withdraw(address account, address lpToken, uint256 amount);
    event GetReward(address account, address lpToken, address rewardToken, uint256 amount);
    event NewIncentiveStrategyStatus(address lpToken, address newStrategy, bool status);
    event NewGlobalIncentiveStrategyStatus(address addr, bool status);

    constructor(IIntswapV1Factory _factory) {
        factory = _factory;
    }

    modifier updateIncentiveStrategies(IERC20 _lpToken, address _account) {
        LPStakingPool storage targetStakingPool = stakingPools[_lpToken];
        for (uint256 i; i < globalIncentiveStrategies.length; i++) {
            if (globalIncentiveStrategies[i].isActive) {
                globalIncentiveStrategies[i].strategy.updatePosition(address(_lpToken), _account);
            }
        }

        for (uint256 i; i < targetStakingPool.incentiveStrategies.length; i++) {
            IncentiveStrategy storage incentiveStrategy = targetStakingPool.incentiveStrategies[i];
            if (incentiveStrategy.isActive) {
                IIntswapV1IncentiveStrategy strategy = incentiveStrategy.strategy;
                strategy.updatePosition(address(_lpToken), _account);
            }
        }
        _;
    }

    modifier isAllowed(bytes32 action) {
        require(factory.isAllowedToCall(address(this), msg.sender, action), "IntswapV1StakingCenter: Only Allowed");
        _;
    }

    function stake(IERC20 _lpToken, uint256 _amount) 
        external 
        nonReentrant
        updateIncentiveStrategies(_lpToken, msg.sender)
        isAllowed(keccak256("stake"))
    {
        require(_amount > 0, "IntswapV1StakingCenter: Cannot stake 0");
        require(factory.isOfficialPair(address(_lpToken)), "IntswapV1StakingCenter: Not Official LP Token");

        LPStakingPool storage targetStakingPool = stakingPools[_lpToken];
        _lpToken.transferFrom(msg.sender, address(this), _amount);
        targetStakingPool.userStakings[msg.sender] += _amount;
        targetStakingPool.totalStakingAmount += _amount;

        emit Stake(msg.sender, address(_lpToken), _amount);
    }

    function withdraw(IERC20 _lpToken, uint256 _amount) 
        external 
        nonReentrant
        updateIncentiveStrategies(_lpToken, msg.sender)
        isAllowed(keccak256("withdraw"))
    {
        require(_amount > 0, "MMFLPStakingPool: Cannot withdraw 0");

        LPStakingPool storage targetStakingPool = stakingPools[_lpToken];
        targetStakingPool.userStakings[msg.sender] -= _amount;
        targetStakingPool.totalStakingAmount -= _amount;     
        _lpToken.transfer(msg.sender, _amount);

        emit Withdraw(msg.sender, address(_lpToken), _amount);
    }

    function getRewards(IERC20 _lpToken) 
        external 
        nonReentrant
        updateIncentiveStrategies(_lpToken, msg.sender)
        isAllowed(keccak256("getRewards"))
    {
        LPStakingPool storage targetStakingPool = stakingPools[_lpToken];
        for (uint256 i; i < globalIncentiveStrategies.length; i++) {
            if (globalIncentiveStrategies[i].isActive) {
                (address globalRewardToken, uint256 globalRewardAmount) = 
                    globalIncentiveStrategies[i].strategy.getReward(address(_lpToken), msg.sender);

                emit GetReward(msg.sender, address(_lpToken), globalRewardToken, globalRewardAmount);
            }
        }

        for (uint256 i; i < targetStakingPool.incentiveStrategies.length; i++) {
            IncentiveStrategy storage incentiveStrategy = targetStakingPool.incentiveStrategies[i];
            if (incentiveStrategy.isActive) {
                IIntswapV1IncentiveStrategy strategy = incentiveStrategy.strategy;
                (address rewardToken, uint256 rewardAmount) = 
                    strategy.getReward(address(_lpToken), msg.sender);

                emit GetReward(msg.sender, address(_lpToken), rewardToken, rewardAmount);
            }
        }
    }

    function updateIncentiveStrategyStatus(
        IERC20 _lpToken, 
        IIntswapV1IncentiveStrategy _newIncentiveStrategy,
        bool _status
    ) 
        external 
        onlyOwner 
    {
        require(address(_newIncentiveStrategy) != address(0), "IntswapV1StakingCenter: Not Zero");
        IncentiveStrategy[] storage incentiveStrategies = stakingPools[_lpToken].incentiveStrategies;

        bool isExisted;
        for (uint256 i; i < incentiveStrategies.length; i++) {
            if (incentiveStrategies[i].strategy == _newIncentiveStrategy) {
                isExisted = true;
                incentiveStrategies[i].isActive = _status;
                break;
            }
        }

        if (!isExisted) {
            incentiveStrategies.push(
                IncentiveStrategy(
                    {
                        strategy: _newIncentiveStrategy,
                        isActive: _status
                    }
                )
            );
        }

        emit NewIncentiveStrategyStatus(address(_lpToken), address(_newIncentiveStrategy), _status);
    }

    function updateGlobalIncentiveStrategyStatus(
        IIntswapV1IncentiveStrategy _globalIncentiveStrategy,
        bool _status
    )
        external
        onlyOwner
    {
        require(address(_globalIncentiveStrategy) != address(0), "IntswapV1StakingCenter: Not Zero");
        bool isExisted;
        for (uint256 i; i < globalIncentiveStrategies.length; i++) {
            if (globalIncentiveStrategies[i].strategy == _globalIncentiveStrategy) {
                isExisted = true;
                globalIncentiveStrategies[i].isActive = _status;
                break;
            }
        }
        if (!isExisted) {
            globalIncentiveStrategies.push(
                IncentiveStrategy(
                    {
                        strategy: _globalIncentiveStrategy,
                        isActive: _status
                    }
                )
            );
        }

        emit NewGlobalIncentiveStrategyStatus(address(_globalIncentiveStrategy), _status);
    } 

    function totalStakingAmount(IERC20 _lpToken) external view returns (uint256) {
        LPStakingPool storage targetStakingPool = stakingPools[_lpToken];
        return targetStakingPool.totalStakingAmount;
    }

    function balanceOf(IERC20 _lpToken, address _account) external view returns (uint256) {
        LPStakingPool storage targetStakingPool = stakingPools[_lpToken];
        return targetStakingPool.userStakings[_account];
    }

    function totalRewardsInfo(
        address _lpToken,
        address _account
    ) 
        external 
        view 
        returns (
            address[] memory, 
            address[] memory, 
            uint256[] memory
        ) 
    {
        LPStakingPool storage targetStakingPool = stakingPools[IERC20(_lpToken)];
        uint256 length = globalIncentiveStrategies.length + targetStakingPool.incentiveStrategies.length;
        uint256 index;
        address[] memory _strategies = new address[](length);
        address[] memory _rewardTokens = new address[](length);
        uint256[] memory _rewardAmounts = new uint256[](length);
        
        for (uint256 i; i < globalIncentiveStrategies.length; i++) {
            (IERC20 globalRewardToken, uint256 globalRewardAmount) = 
                globalIncentiveStrategies[i].strategy.earned(_lpToken, _account);
            _strategies[index] = address(globalIncentiveStrategies[i].strategy);
            _rewardTokens[index] = address(globalRewardToken);
            _rewardAmounts[index] = globalRewardAmount;
            index += 1;
        }

        for (uint256 i; i < targetStakingPool.incentiveStrategies.length; i++) {
            (IERC20 rewardToken, uint256 rewardAmount) = 
                targetStakingPool.incentiveStrategies[i].strategy.earned(_lpToken, _account);
            _strategies[index] = address(targetStakingPool.incentiveStrategies[i].strategy);
            _rewardTokens[index] = address(rewardToken);
            _rewardAmounts[index] = rewardAmount;
            index += 1;
        }

        return (
            _strategies,
            _rewardTokens,
            _rewardAmounts
        );
    }
}
