// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract BuyIncentiveStrategy is Ownable, ReentrancyGuard {
    address[] public officalPairs;
    mapping(address => bool) public isOfficalPairs;
    address public factory;
    IERC20 public rewardToken;

    uint256 public startTime;
    uint256 public constant PERIOD = 1 days;

    struct UserReward {
        uint256 recordedEpoch;
        uint256 confirmedRewards;
        uint256 unConfirmedVolumn;
        uint256 claimedRewards;
    }

    struct RewardEpoch {
        uint256 startEpoch;
        uint256 endEpoch;
        uint256 rewardRate;
    }

    struct Incentive {
        address lpToken;
        IERC20 rewardToken;
        uint256 startEpoch;
        uint256 endEpoch;
        RewardEpoch[] rewardRates;
        mapping(uint256 => uint256) totalRecordVolumn;
        mapping(address => UserReward) userRecordVolumn;
        bool isActive;
    }

    mapping(address => Incentive) public incentives;

    event GetReward(address lpToken, address from, uint256 rewards);

    function start(address _factory, IERC20 _rewardToken, uint256 _startTime) external onlyOwner {
        factory = _factory;
        rewardToken = _rewardToken;
        startTime = _startTime;
    }

    function setTargetPairStatus(address _pair, bool _isActive) external onlyOwner {
        Incentive storage newIncentive = incentives[_pair];
        newIncentive.isActive = _isActive;
    }

    function createNewIncentive(
        address[] memory _pairs, 
        uint256[] memory _startEpochs, 
        uint256[] memory _endEpochs,
        uint256[][] memory _rewardEpochStartEpochs,
        uint256[][] memory _rewardEpochEndEpochs,
        uint256[][] memory _rewardEpochRewardRates
    ) 
        external 
        onlyOwner 
    {
        uint256 totalRewards;
        for (uint256 i; i < _pairs.length; i++) {
            if (!isOfficalPairs[_pairs[i]]) {
                isOfficalPairs[_pairs[i]] = true;
                officalPairs.push(_pairs[i]);
            }

            Incentive storage newIncentive = incentives[_pairs[i]];
            
            newIncentive.lpToken = _pairs[i];
            newIncentive.startEpoch = _startEpochs[i];
            newIncentive.endEpoch = _endEpochs[i];
            newIncentive.rewardToken = rewardToken;
            newIncentive.isActive = true;
            for (uint256 j; j < _rewardEpochStartEpochs[i].length; j++) {
                newIncentive.rewardRates.push(
                    RewardEpoch({
                        startEpoch: _rewardEpochStartEpochs[i][j],
                        endEpoch: _rewardEpochEndEpochs[i][j],
                        rewardRate: _rewardEpochRewardRates[i][j] 
                    })
                );

                totalRewards += _rewardEpochRewardRates[i][j];
            }
        }    

        rewardToken.transferFrom(msg.sender, address(this), totalRewards);
    }

    function hook(bytes32 action, bytes memory data) external {
        require(msg.sender == factory, "BuyIncentiveStrategy: Only factory.");
        
        if (action == keccak256("Buy")) {
            (address trader, address lpToken, ,uint256 baseTokenInputAmount, , ) = 
                abi.decode(data, (address, address, uint256, uint256, uint256, uint256));
            
            _updateRewards(lpToken, trader, baseTokenInputAmount);
        }
    }

    function getRewards() external returns (uint256 totalRewards) {
        for (uint256 i; i < officalPairs.length; i++) {
            totalRewards += getReward(officalPairs[i]);
        }
    }

    function getReward(address _targetPair) public returns (uint256) {
        _updateRewards(_targetPair, msg.sender, 0);

        Incentive storage targetIncentive = incentives[_targetPair];
        UserReward storage targetUserRewards = targetIncentive.userRecordVolumn[msg.sender];
        uint256 claimableRewards = targetUserRewards.confirmedRewards - targetUserRewards.claimedRewards;

        targetUserRewards.claimedRewards = targetUserRewards.confirmedRewards;

        targetIncentive.rewardToken.transfer(msg.sender, claimableRewards);

        emit GetReward(_targetPair, msg.sender, claimableRewards);

        return claimableRewards;
    }

    function earnedAll(address _account) external view returns (uint256 totalRewards) {
        for (uint256 i; i < officalPairs.length; i++) {
            totalRewards += earned(officalPairs[i], _account);
        }
    }

    function earned(address _lpToken, address _account) public view returns (uint256 totalReward) {
        Incentive storage targetIncentive = incentives[_lpToken];
        if (targetIncentive.isActive && block.timestamp > startTime) {
            uint256 currentEpoch = (block.timestamp - startTime) / PERIOD;
            UserReward storage targetUserRewards = targetIncentive.userRecordVolumn[_account];
            uint256 unRecordRewards;

            if (currentEpoch != targetUserRewards.recordedEpoch && targetIncentive.totalRecordVolumn[targetUserRewards.recordedEpoch] > 0) {
                uint256 currentRewardRate = _getTargetRewardRate(targetUserRewards.recordedEpoch, targetIncentive);
                
                unRecordRewards += currentRewardRate * 
                    targetUserRewards.unConfirmedVolumn / 
                    targetIncentive.totalRecordVolumn[targetUserRewards.recordedEpoch];
            }

            totalReward = targetUserRewards.confirmedRewards + unRecordRewards - targetUserRewards.claimedRewards;
        }
    }

    function _updateRewards(address _lpToken, address _account, uint256 _tradingVolumn) internal {
        Incentive storage targetIncentive = incentives[_lpToken];
        
        if (targetIncentive.isActive && block.timestamp > startTime) {
            uint256 currentEpoch = (block.timestamp - startTime) / PERIOD;
            UserReward storage targetUserRewards = targetIncentive.userRecordVolumn[_account];
            
            if (currentEpoch != targetUserRewards.recordedEpoch) {
                if (targetIncentive.totalRecordVolumn[targetUserRewards.recordedEpoch] > 0) {
                    
                    uint256 currentRewardRate = _getTargetRewardRate(targetUserRewards.recordedEpoch, targetIncentive);
                    
                    targetUserRewards.confirmedRewards += currentRewardRate * 
                        targetUserRewards.unConfirmedVolumn / 
                        targetIncentive.totalRecordVolumn[targetUserRewards.recordedEpoch];
                }
            }

            if (currentEpoch >= targetIncentive.startEpoch && currentEpoch <= targetIncentive.endEpoch) {
                targetIncentive.totalRecordVolumn[currentEpoch] += _tradingVolumn;
                if (currentEpoch == targetUserRewards.recordedEpoch) {
                    targetUserRewards.unConfirmedVolumn += _tradingVolumn;
                } else {
                    targetUserRewards.unConfirmedVolumn = _tradingVolumn;
                }
            }

            targetUserRewards.recordedEpoch = currentEpoch;
        }
    }

    function _getTargetRewardRate(uint256 _epochNum, Incentive storage _incentive) internal view returns (uint256 targetRewardRate) {
        for (uint256 i; i < _incentive.rewardRates.length; i++) {
            if (_incentive.rewardRates[i].startEpoch <= _epochNum && _incentive.rewardRates[i].endEpoch >= _epochNum) {
                targetRewardRate = _incentive.rewardRates[i].rewardRate;
            }
        }
    }
}
