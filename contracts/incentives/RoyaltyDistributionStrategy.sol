// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "solmate/src/utils/FixedPointMathLib.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../interfaces/IIntswapV1Factory.sol";
import "../interfaces/IRoyaltyDistributionStrategy.sol";
import "../interfaces/IIntswapV1StakingCenter.sol";

contract RoyaltyDistributionStrategy is IRoyaltyDistributionStrategy, Ownable, ReentrancyGuard {
    address public constant NATIVE_ETH = address(0x000000000000000000000000000000000000800A);
    struct Incentive {
        address lpToken;
        uint256 startTime;
        uint256 cumulativeRewards; 
        uint256 lastRewardTime;
        uint256 unDistributedRewards;
        uint256 rewardPerTokenStored;
        mapping(address => uint256) userRewardPerTokenPaid;
        mapping(address => uint256) userUnClaimedRewards;
    }

    string public constant name = "RoyaltyDistributionStrategy";

    IIntswapV1Factory public immutable factory;
    IIntswapV1StakingCenter public immutable stakingCenter;
    address public immutable royaltyVault;

    mapping(address => Incentive) public incentives;

    event UpdatePosition(address account, address lpToken);
    event RewardPaid(address account, address lpToken, address rewardToken, uint256 rewardAmount);

    modifier onlyStakingCenter() {
        require(msg.sender == address(stakingCenter), "FixedRewardRateStrategy: Not Staking Center");
        _;
    }

    modifier onlyRoyaltyVault() {
        require(msg.sender == royaltyVault, "FixedRewardRateStrategy: Not Royalty Vault");
        _;
    }

    modifier updateRewards(address _lpToken, address _account) {
        Incentive storage targetIncentive = incentives[_lpToken];
        (, targetIncentive.userUnClaimedRewards[_account]) = earned(_lpToken, _account);
        targetIncentive.rewardPerTokenStored = _rewardPerToken(_lpToken);
        targetIncentive.userRewardPerTokenPaid[_account] = targetIncentive.rewardPerTokenStored;
        targetIncentive.lastRewardTime = block.timestamp;
        targetIncentive.unDistributedRewards = 0;
        _;
    }

    constructor(
        IIntswapV1Factory _factory, 
        IIntswapV1StakingCenter _stakingCenter,
        address _royaltyVault
    ) {
        factory = _factory;
        stakingCenter = _stakingCenter;
        royaltyVault = _royaltyVault;
    }

    receive() external payable {}

    function distribute(address _lpToken, uint256 _amount) external onlyRoyaltyVault {
        Incentive storage targetIncentive = incentives[_lpToken];
        targetIncentive.unDistributedRewards += _amount;
        uint256 nowTime = block.timestamp;
        if (nowTime - targetIncentive.startTime > 31536000){
            targetIncentive.startTime = nowTime;
            targetIncentive.cumulativeRewards = 0;
        }

        targetIncentive.cumulativeRewards += _amount;
    }

    function updatePosition(address _lpToken, address _account) 
        external
        nonReentrant
        onlyStakingCenter 
        updateRewards(_lpToken, _account) 
    {
        emit UpdatePosition(_account, address(_lpToken));
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
        rewardAmount = targetIncentive.userUnClaimedRewards[_account];
        rewardTokenAddr = NATIVE_ETH;
        if (rewardAmount > 0) {
            targetIncentive.userUnClaimedRewards[_account] = 0;
            
            _safeTransferETH(_account, rewardAmount);
            emit RewardPaid(_account, address(_lpToken), NATIVE_ETH, rewardAmount);
        }
    }

    function earned(address _lpToken, address _account) public view returns (IERC20, uint256) {
        Incentive storage targetIncentive = incentives[_lpToken];
        uint256 userNotPaidRewardPerToken = _rewardPerToken(_lpToken) - 
            targetIncentive.userRewardPerTokenPaid[_account];

        uint256 userBalance = stakingCenter.balanceOf(IERC20(_lpToken), _account);
        uint256 userUnClaimedRewards = targetIncentive.userUnClaimedRewards[_account];

        return (
            IERC20(NATIVE_ETH),
            FixedPointMathLib.mulWadDown(userBalance, userNotPaidRewardPerToken) + userUnClaimedRewards
        );
    }

    function estimatedOneYearRewards(address _lpToken) external view returns (IERC20, uint256) {
        Incentive storage targetIncentive = incentives[_lpToken];
        return (
            IERC20(NATIVE_ETH),
            targetIncentive.cumulativeRewards * 31536000 / (block.timestamp - targetIncentive.startTime)
        );
    }

    function _safeTransferETH(address to, uint value) internal {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = to.call{value: value}("");

        require(success, "IntswapV1Pair: Transfer ETH Failed");
    }

    function _rewardPerToken(address _lpToken) internal view returns (uint256 newRewardPerTokenStored) {
        uint256 totalStakingAmount = stakingCenter.totalStakingAmount(IERC20(_lpToken));
        Incentive storage targetIncentive = incentives[_lpToken];
        if (totalStakingAmount == 0) {
            newRewardPerTokenStored = targetIncentive.rewardPerTokenStored;
        } else {
            uint256 addend = FixedPointMathLib.divWadDown(
                targetIncentive.unDistributedRewards, 
                totalStakingAmount
            );

            newRewardPerTokenStored = targetIncentive.rewardPerTokenStored + addend;
        }
    }
}
