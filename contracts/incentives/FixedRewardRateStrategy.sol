// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "solmate/src/utils/FixedPointMathLib.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../interfaces/IIntswapV1Factory.sol";
import "../interfaces/IIntswapV1IncentiveStrategy.sol";
import "../interfaces/IIntswapV1StakingCenter.sol";

contract FixedRewardRateStrategy is IIntswapV1IncentiveStrategy, AccessControl, ReentrancyGuard {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant CREATE_NEW_INCENTIVE = keccak256("CREATE_NEW_INCENTIVE");
    string public name = "FixedRewardRateStrategy";

    struct Incentive {
        address lpToken;
        IERC20 rewardToken;
        uint256 epochNum;
        uint256 startTime;
        uint256 endTime;
        uint256 lastRewardTime;
        uint256 rewardRate;
        uint256 rewardPerTokenStored;
        mapping(address => uint256) userRewardPerTokenPaid;
        mapping(address => uint256) userUnClaimedRewards;
        bool isActive;
    }

    IIntswapV1Factory public factory;
    IIntswapV1StakingCenter public stakingCenter;
    mapping(address => Incentive) public incentives;

    event NewRewardEpoch(
        address lpToken,
        IERC20 rewardToken,
        uint256 epochNum,
        uint256 startTime,
        uint256 duration,
        uint256 totalRewards
    );

    event NotActive(address lpToken);
    event UpdatePosition(address account, address lpToken);
    event RewardPaid(address account, address lpToken, address rewardToken, uint256 rewardAmount);

    modifier onlyStakingCenter() {
        require(msg.sender == address(stakingCenter), "FixedRewardRateStrategy: Not Staking Center");
        _;
    }

    modifier updateRewards(address _lpToken, address _account) {
        Incentive storage targetIncentive = incentives[_lpToken];
        if (targetIncentive.isActive) {
            targetIncentive.rewardPerTokenStored = _rewardPerToken(_lpToken);
            targetIncentive.lastRewardTime = _lastTimeRewardApplicable(targetIncentive);
            (, targetIncentive.userUnClaimedRewards[_account]) = earned(_lpToken, _account);
            targetIncentive.userRewardPerTokenPaid[_account] = targetIncentive.rewardPerTokenStored;
        }
        _;
    }

    constructor(IIntswapV1Factory _factory, IIntswapV1StakingCenter _stakingCenter) {
        factory = _factory;
        stakingCenter = _stakingCenter;
        _setRoleAdmin(CREATE_NEW_INCENTIVE, ADMIN_ROLE);
        _setupRole(ADMIN_ROLE, _msgSender());
        _setupRole(CREATE_NEW_INCENTIVE, _msgSender());
    }

    function createIncentive(
        address[] memory _lpTokens,
        IERC20[] memory _rewardTokens,
        uint256[] memory _startTimes,
        uint256[] memory _durations,
        uint256[] memory _rewardAmounts
    ) 
        external 
        nonReentrant 
        onlyRole(CREATE_NEW_INCENTIVE) 
    {
        for (uint256 i; i < _lpTokens.length; i++) {
            _createIncentive(
                _lpTokens[i],
                _rewardTokens[i],
                _startTimes[i],
                _durations[i],
                _rewardAmounts[i]
            );
        }
    }

    function updateIncentive(
        address _lpToken,
        uint256 _startTime,
        uint256 _duration,
        uint256 _rewardAmount
    ) 
        external 
        nonReentrant 
        onlyRole(CREATE_NEW_INCENTIVE)  
    {
        Incentive storage targetIncentive = incentives[_lpToken];
        require(targetIncentive.isActive, "FixedRewardRateStrategy: Not Created");
        require(block.timestamp > targetIncentive.endTime, "FixedRewardRateStrategy: Last Epoch Not Finished");
        require(_startTime > block.timestamp, "FixedRewardRateStrategy: Expired");
        require(_duration > 0, "FixedRewardRateStrategy: Too Short");
        require(_rewardAmount > 0, "FixedRewardRateStrategy: Not Zero");

        targetIncentive.rewardToken.transferFrom(msg.sender, address(this), _rewardAmount);
        
        targetIncentive.startTime = _startTime;
        targetIncentive.endTime = _startTime + _duration;
        targetIncentive.lastRewardTime = targetIncentive.startTime;
        targetIncentive.rewardRate = _rewardAmount / _duration;
        targetIncentive.epochNum += 1;

        emit NewRewardEpoch(
            _lpToken, 
            targetIncentive.rewardToken, 
            targetIncentive.epochNum, 
            _startTime, 
            _duration, 
            _rewardAmount
        );
    }

    function updatePosition(address _lpToken, address _account) 
        external
        nonReentrant
        onlyStakingCenter 
        updateRewards(_lpToken, _account) 
    {
        Incentive storage targetIncentive = incentives[_lpToken];
        if (targetIncentive.isActive) {
            emit UpdatePosition(_account, address(_lpToken));
        } else {
            emit NotActive(address(_lpToken));
        }
    }

    function getReward(address _lpToken, address _account) 
        external 
        nonReentrant
        onlyStakingCenter
        updateRewards(_lpToken, _account) 
        returns (
            address rewardTokenAddr,
            uint256 rewardAmount
        )
    {
        Incentive storage targetIncentive = incentives[_lpToken];
        if (targetIncentive.isActive) {
            rewardAmount = targetIncentive.userUnClaimedRewards[_account];
            IERC20 rewardToken = targetIncentive.rewardToken;
            rewardTokenAddr = address(rewardToken);
            if (rewardAmount > 0) {
                targetIncentive.userUnClaimedRewards[_account] = 0;
                rewardToken.transfer(_account, rewardAmount);
                emit RewardPaid(_account, address(_lpToken), address(rewardToken), rewardAmount);
            }
        } else {
            emit NotActive(address(_lpToken));
        }
    }

    function earned(address _lpToken, address _account) public view returns (IERC20, uint256) {
        Incentive storage targetIncentive = incentives[_lpToken];
        uint256 userNotPaidRewardPerToken = _rewardPerToken(_lpToken) - targetIncentive.userRewardPerTokenPaid[_account];
        uint256 userBalance = stakingCenter.balanceOf(IERC20(_lpToken), _account);
        uint256 userUnClaimedRewards = targetIncentive.userUnClaimedRewards[_account];

        return (
            targetIncentive.rewardToken,
            FixedPointMathLib.mulWadDown(userBalance, userNotPaidRewardPerToken) + userUnClaimedRewards
        );
    }

    function estimatedOneYearRewards(address _lpToken) external view returns (IERC20, uint256) {
        Incentive storage targetIncentive = incentives[_lpToken];
        uint256 nowTime = block.timestamp;
        return (
            targetIncentive.rewardToken,
            (targetIncentive.startTime < nowTime && nowTime < targetIncentive.endTime) ? targetIncentive.rewardRate * 31536000 : 0
        );
    }

    function _lastTimeRewardApplicable(Incentive storage _incentive) internal view returns (uint256) {
        uint256 nowTime = block.timestamp;
        uint256 startTime = _incentive.startTime;
        uint256 endTime = _incentive.endTime;
        return (nowTime < startTime) ? startTime : (nowTime > endTime) ? endTime : nowTime;
    }

    function _rewardPerToken(address _lpToken) internal view returns (uint256 newRewardPerTokenStored) {
        uint256 totalStakingAmount = stakingCenter.totalStakingAmount(IERC20(_lpToken));
        Incentive storage targetIncentive = incentives[_lpToken];
        if (totalStakingAmount == 0) {
            newRewardPerTokenStored = targetIncentive.rewardPerTokenStored;
        } else {
            uint256 deltaTime = _lastTimeRewardApplicable(targetIncentive) - targetIncentive.lastRewardTime;
            uint256 addend = FixedPointMathLib.divWadDown(deltaTime * targetIncentive.rewardRate, totalStakingAmount);
            newRewardPerTokenStored = targetIncentive.rewardPerTokenStored + addend;
        }
    }

    function _createIncentive(
        address _lpToken,
        IERC20 _rewardToken,
        uint256 _startTime,
        uint256 _duration,
        uint256 _rewardAmount
    ) 
        internal
    {
        require(_startTime > block.timestamp, "FixedRewardRateStrategy: Expired");
        require(_duration > 0, "FixedRewardRateStrategy: Too short");
        require(_rewardAmount > 0, "FixedRewardRateStrategy: Not Zero");
        require(factory.isOfficialPair(address(_lpToken)), "FixedRewardRateStrategy: Not Official LP Token");

        Incentive storage newIncentive = incentives[_lpToken];
        require(!newIncentive.isActive, "FixedRewardRateStrategy: Already Created");

        _rewardToken.transferFrom(msg.sender, address(this), _rewardAmount);

        newIncentive.lpToken = _lpToken;
        newIncentive.rewardToken = _rewardToken;
        newIncentive.startTime = _startTime;
        newIncentive.endTime = _startTime + _duration;
        newIncentive.lastRewardTime = newIncentive.startTime;
        newIncentive.rewardRate = _rewardAmount / _duration;
        newIncentive.isActive = true;

        emit NewRewardEpoch(
            _lpToken, 
            _rewardToken, 
            0, 
            _startTime, 
            _duration, 
            _rewardAmount
        );
    }
}
