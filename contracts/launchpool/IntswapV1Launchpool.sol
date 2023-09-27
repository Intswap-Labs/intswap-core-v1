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


contract IntswapV1Launchpool is AccessControl, ReentrancyGuard {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant CREATE_NEW_INCENTIVE = keccak256("CREATE_NEW_INCENTIVE");
    string public name = "Intswap Launch Pool";

    struct Incentive {
        address lpToken;
        IERC721 rewardToken;
        uint256 epochNum;
        uint256 startTime;
        uint256 totalRewardAmount;
        uint256 remainAmount;
        uint256 lastRewardTime;
        uint256 rewardRate;
        uint256 rewardPerTokenStored;

        mapping(address => mapping(uint256 => uint256)) userRewardPerTokenPaid;
        mapping(address => mapping(uint256 => uint256)) userUnClaimedRewards;
        bool isActive;
    }

    IIntswapV1Factory public factory;
    IIntswapV1StakingCenter public stakingCenter;
    mapping(address => Incentive) public incentives;

    event NewRewardEpoch(
        address lpToken,
        IERC721 rewardToken,
        uint256 epochNum,
        uint256 startTime,
        uint256 rewardRate,
        uint256 totalRewards
    );

    event NotActive(address lpToken);
    event UpdatePosition(address account, address lpToken);
    event RewardPaid(address account, address lpToken, address rewardToken, uint256 rewardAmount);

    modifier onlyStakingCenter() {
        require(msg.sender == address(stakingCenter), "IntswapV1Launchpool: Not Staking Center");
        _;
    }

    modifier updateRewards(address _lpToken, address _account) {
        Incentive storage targetIncentive = incentives[_lpToken];
        if (targetIncentive.isActive) {
            targetIncentive.rewardPerTokenStored = _rewardPerToken(_lpToken);
            targetIncentive.lastRewardTime = _lastTimeRewardApplicable(targetIncentive);
            (, targetIncentive.userUnClaimedRewards[_account][targetIncentive.epochNum]) = earned(_lpToken, _account);
            targetIncentive.userRewardPerTokenPaid[_account][targetIncentive.epochNum] = targetIncentive.rewardPerTokenStored;
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
        IERC721[] memory _rewardTokens,
        uint256[] memory _startTimes,
        uint256[] memory _rewardRate,
        uint256[] memory _rewardAmounts,
        uint256[][] memory _tokenIds
    ) 
        external 
        nonReentrant 
        onlyRole(CREATE_NEW_INCENTIVE) 
    {
        for (uint256 i; i < _lpTokens.length; i++) {
            _sendSpecificNFTsToRecipient(_rewardTokens[i], msg.sender, address(this), _tokenIds[i], _tokenIds[i].length);

            _createIncentive(
                _lpTokens[i],
                _rewardTokens[i],
                _startTimes[i],
                _rewardRate[i],
                _rewardAmounts[i]
            );
        }
    }

    function updateIncentive(
        address _lpToken,
        uint256 _startTime,
        uint256 _rewardRate,
        uint256 _rewardAmount,
        uint256[] memory _tokenIds
    ) 
        external 
        nonReentrant 
        onlyRole(CREATE_NEW_INCENTIVE)  
    {
        Incentive storage targetIncentive = incentives[_lpToken];

        require(targetIncentive.isActive, "IntswapV1Launchpool: Not Created");
        require(_startTime > block.timestamp, "IntswapV1Launchpool: Expired");
        require(_rewardAmount > 0, "IntswapV1Launchpool: Not Zero");
        require(targetIncentive.remainAmount == 0, "IntswapV1Launchpool: Not Finished");


        _sendSpecificNFTsToRecipient(targetIncentive.rewardToken, msg.sender, address(this), _tokenIds, _tokenIds.length);
        
        targetIncentive.startTime = _startTime;
        targetIncentive.lastRewardTime = targetIncentive.startTime;
        targetIncentive.rewardRate = _rewardRate;
        targetIncentive.totalRewardAmount = _rewardAmount;
        targetIncentive.remainAmount = _rewardAmount;
        targetIncentive.rewardPerTokenStored = 0;
        targetIncentive.epochNum += 1;

        emit NewRewardEpoch(
            _lpToken, 
            targetIncentive.rewardToken, 
            targetIncentive.epochNum, 
            _startTime, 
            _rewardRate, 
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
        returns (
            address rewardTokenAddr,
            uint256 rewardAmount
        )
    {
        Incentive storage targetIncentive = incentives[_lpToken];
        if (targetIncentive.isActive) {
            rewardAmount = targetIncentive.userUnClaimedRewards[_account][targetIncentive.epochNum];
            IERC721 rewardToken = targetIncentive.rewardToken;
            rewardTokenAddr = address(rewardToken);
            rewardAmount = (targetIncentive.remainAmount * FixedPointMathLib.WAD < rewardAmount) ? targetIncentive.remainAmount * FixedPointMathLib.WAD : rewardAmount;
            // if (rewardAmount > 0) {
            //     targetIncentive.userUnClaimedRewards[_account][targetIncentive.epochNum] = 0;
            //     // rewardToken.transfer(_account, rewardAmount);
            //     emit RewardPaid(_account, address(_lpToken), address(rewardToken), rewardAmount);
            // }
        } else {
            emit NotActive(address(_lpToken));
        }
    }

    function getRewardByOwner(address _lpToken, uint256[] memory _tokenIds) 
        external 
        nonReentrant
        updateRewards(_lpToken, msg.sender) 
        returns (
            address rewardTokenAddr,
            uint256 rewardAmount
        )
    {
        Incentive storage targetIncentive = incentives[_lpToken];
        if (targetIncentive.isActive) {
            rewardAmount = targetIncentive.userUnClaimedRewards[msg.sender][targetIncentive.epochNum];
            IERC721 rewardToken = targetIncentive.rewardToken;
            rewardTokenAddr = address(rewardToken);
            rewardAmount = (targetIncentive.remainAmount * FixedPointMathLib.WAD < rewardAmount) ? targetIncentive.remainAmount * FixedPointMathLib.WAD : rewardAmount;

            uint256 nftRewardAmount = rewardAmount / FixedPointMathLib.WAD;
            uint256 unClaimedReward = rewardAmount % FixedPointMathLib.WAD;
            if (nftRewardAmount > 0) {
                targetIncentive.userUnClaimedRewards[msg.sender][targetIncentive.epochNum] = unClaimedReward;
                // rewardToken.transfer(_account, rewardAmount);
                _sendSpecificNFTsToRecipient(rewardToken, address(this), msg.sender, _tokenIds, nftRewardAmount);

                targetIncentive.remainAmount = targetIncentive.remainAmount - nftRewardAmount;
                emit RewardPaid(msg.sender, address(_lpToken), address(rewardToken), nftRewardAmount);
            }
        } else {
            emit NotActive(address(_lpToken));
        }
    }

    function earned(address _lpToken, address _account) public view returns (IERC721, uint256) {
        Incentive storage targetIncentive = incentives[_lpToken];
        uint256 userNotPaidRewardPerToken = _rewardPerToken(_lpToken) - targetIncentive.userRewardPerTokenPaid[_account][targetIncentive.epochNum];
        uint256 userBalance = stakingCenter.balanceOf(IERC20(_lpToken), _account);
        uint256 userUnClaimedRewards = targetIncentive.userUnClaimedRewards[_account][targetIncentive.epochNum];

        uint256 rewardAmount = FixedPointMathLib.mulWadDown(userBalance, userNotPaidRewardPerToken) + userUnClaimedRewards;
        rewardAmount = (targetIncentive.remainAmount * FixedPointMathLib.WAD < rewardAmount) ? targetIncentive.remainAmount * FixedPointMathLib.WAD : rewardAmount;

        return (
            targetIncentive.rewardToken,
            rewardAmount
        );
    }

    function estimatedOneYearRewards(address _lpToken) external view returns (IERC721, uint256) {
        Incentive storage targetIncentive = incentives[_lpToken];
        uint256 nowTime = block.timestamp;
        return (
            targetIncentive.rewardToken,
            (targetIncentive.startTime < nowTime) ? targetIncentive.rewardRate * 31536000 : 0
        );
    }

    function _lastTimeRewardApplicable(Incentive storage _incentive) internal view returns (uint256) {
        uint256 nowTime = block.timestamp;
        uint256 startTime = _incentive.startTime;
        return (nowTime < startTime) ? startTime : nowTime;
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
        IERC721 _rewardToken,
        uint256 _startTime,
        uint256 _rewardRate,
        uint256 _rewardAmount
    ) 
        internal
    {
        require(_startTime > block.timestamp, "IntswapV1Launchpool: Expired");
        require(_rewardRate > 0, "IntswapV1Launchpool: RewardRate not zero");
        require(_rewardAmount > 0, "IntswapV1Launchpool: Not Zero");
        require(factory.isOfficialPair(address(_lpToken)), "IntswapV1Launchpool: Not Official LP Token");

        Incentive storage newIncentive = incentives[_lpToken];
        require(!newIncentive.isActive, "IntswapV1Launchpool: Already Created");

        newIncentive.lpToken = _lpToken;
        newIncentive.rewardToken = _rewardToken;
        newIncentive.startTime = _startTime;
        newIncentive.lastRewardTime = newIncentive.startTime;
        newIncentive.rewardRate = _rewardRate;
        newIncentive.totalRewardAmount = _rewardAmount;
        newIncentive.remainAmount = _rewardAmount;
        newIncentive.isActive = true;

        emit NewRewardEpoch(
            _lpToken, 
            _rewardToken, 
            0, 
            _startTime, 
            _rewardRate, 
            _rewardAmount
        );
    }

    function _sendSpecificNFTsToRecipient(
        IERC721 nft,
        address nftSender,
        address nftRecipient,
        uint256[] memory nftIds,
        uint256 length
    ) internal {
        for (uint256 i; i < length; ) {
            nft.transferFrom(nftSender, nftRecipient, nftIds[i]);

            unchecked {
                ++i;
            }
        }
    }
}