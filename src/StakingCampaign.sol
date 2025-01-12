// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "lib/forge-std/src/console.sol";

contract MultiTokenStakingCampaign is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    uint256 constant SCALE_FACTOR = 10 ** 18;

    struct CampaignMetadata {
        address rewardToken;
        uint256 startTime;
        uint256 endTime;
        uint256 rewardClaimEnd;
        uint256 totalRewards;
        uint256 unclaimedRewards;
        address stakingToken;
    }

    struct Campaign {
        CampaignMetadata metadata;
        mapping(address => uint256) userTotalStaked;
        mapping(address => uint256) userAccumulatedRewardWeight;
        uint256 totalWeight;
        uint256 totalRewardAllocated;
        uint256 totalStaked;
        uint256 rewardCoefficient;
    }

    Campaign[] private campaigns;
    address public WETH;

    constructor(address initialOwner, address _WETH) Ownable(initialOwner) {
        WETH = _WETH;
    }

    event CampaignCreated(
        uint256 campaignId,
        uint256 startTime,
        uint256 endTime,
        uint256 rewardClaimEnd,
        uint256 totalRewards
    );

    event TokensStaked(
        uint256 campaignId,
        address staker,
        address tokenAddress,
        uint256 amount
    );

    event RewardsClaimed(uint256 campaignId, address staker, uint256 reward);
    event UnclaimedRewardsClaimed(uint256 campaignId, uint256 amount);
    event TokensReturned(uint256 campaignId, address staker);

    function createCampaign(
        address _rewardToken,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _rewardClaimEnd,
        uint256 _totalRewards,
        address _stakingToken
    ) external onlyOwner {
        require(
            _startTime > block.timestamp,
            "Start time must be in the future"
        );
        require(_endTime > _startTime, "End time must be after start time");
        require(
            _rewardClaimEnd > _endTime,
            "Reward claim end time must be after end time"
        );
        require(_totalRewards > 0, "Total rewards must be greater than zero");
        require(_rewardToken != address(0), "Invalid reward token address");
        require(
            _rewardToken.code.length > 0,
            "Reward token must be a contract"
        );
        require(
            IERC20(_rewardToken).balanceOf(msg.sender) >= _totalRewards,
            "Insufficient reward token balance"
        );

        IERC20(_rewardToken).safeTransferFrom(
            msg.sender,
            address(this),
            _totalRewards
        );

        campaigns.push();
        Campaign storage newCampaign = campaigns[campaigns.length - 1];
        newCampaign.metadata.rewardToken = _rewardToken;
        newCampaign.metadata.startTime = _startTime;
        newCampaign.metadata.endTime = _endTime;
        newCampaign.metadata.rewardClaimEnd = _rewardClaimEnd;
        newCampaign.metadata.totalRewards = _totalRewards;
        newCampaign.metadata.unclaimedRewards = _totalRewards;
        newCampaign.metadata.stakingToken = _stakingToken;

        newCampaign.rewardCoefficient = 1 * SCALE_FACTOR;

        emit CampaignCreated(
            campaigns.length - 1,
            _startTime,
            _endTime,
            _rewardClaimEnd,
            _totalRewards
        );
    }

    function stakeTokens(
        uint256 _campaignId,
        uint256 _amount
    ) external payable nonReentrant {
        Campaign storage campaign = campaigns[_campaignId];
        require(
            block.timestamp >= campaign.metadata.startTime,
            "Campaign has not started"
        );
        require(
            block.timestamp <= campaign.metadata.endTime,
            "Campaign has ended"
        );
        require(
            campaign.userTotalStaked[msg.sender] + _amount >=
                campaign.userTotalStaked[msg.sender],
            "Staking amount overflow"
        );

        address _tokenAddress = campaign.metadata.stakingToken;
        if (msg.value > 0) {
            require(msg.value == _amount, "Incorrect ETH amount sent");
            IWETH(WETH).deposit{value: _amount}();
            _tokenAddress = WETH;
        } else {
            require(msg.value == 0, "WithETH should not be sent");
            require(_amount > 0, "Invalid staking amount");
            IERC20(_tokenAddress).safeTransferFrom(
                msg.sender,
                address(this),
                _amount
            );
        }

        uint256 stakingDuration = campaign.metadata.endTime - block.timestamp;
        require(stakingDuration > 0, "Invalid staking duration");
        require(_amount > 0, "Invalid staking amount");

        uint256 newWeight = _amount * stakingDuration;
        require(
            campaign.totalWeight + newWeight >= campaign.totalWeight,
            "Weight overflow"
        );

        campaign.totalWeight += newWeight;
        campaign.userAccumulatedRewardWeight[msg.sender] += newWeight;

        campaign.userTotalStaked[msg.sender] += _amount;
        campaign.totalStaked += _amount;

        emit TokensStaked(_campaignId, msg.sender, _tokenAddress, _amount);
    }

    function calculateFinalReward(
        uint256 userWeight,
        uint256 totalWeight,
        uint256 totalRewards,
        uint256 rewardCoefficient
    ) internal pure returns (uint256) {
        console.log("userWeight: %d", userWeight);
        console.log("totalWeight: %d", totalWeight);
        console.log("totalRewards: %d", totalRewards);
        console.log("rewardCoefficient: %d", rewardCoefficient);

        return
            ((userWeight * rewardCoefficient * totalRewards) /
                (totalWeight == 0 ? 1 : totalWeight)) / SCALE_FACTOR;
    }

    function claimRewards(uint256 _campaignId) external nonReentrant {
        Campaign storage campaign = campaigns[_campaignId];
        require(
            block.timestamp > campaign.metadata.endTime,
            "Campaign has not ended"
        );
        require(
            block.timestamp <= campaign.metadata.rewardClaimEnd,
            "Reward claim period has ended"
        );
        uint256 userWeight = campaign.userAccumulatedRewardWeight[msg.sender];
        require(userWeight > 0, "No rewards to claim");

        uint256 remainingRewards = campaign.metadata.unclaimedRewards;
        uint256 remainingWeight = campaign.totalWeight - userWeight;
        if (remainingWeight > 0) {
            campaign.rewardCoefficient =
                (remainingRewards * SCALE_FACTOR) /
                campaign.metadata.totalRewards -
                campaign.totalRewardAllocated;
        }

        uint256 finalReward = calculateFinalReward(
            userWeight,
            campaign.totalWeight,
            campaign.metadata.unclaimedRewards,
            campaign.rewardCoefficient
        );

        console.log("user finalReward: %d", finalReward);

        campaign.metadata.unclaimedRewards -= finalReward;
        campaign.totalWeight -= userWeight;
        campaign.userAccumulatedRewardWeight[msg.sender] = 0;

        IERC20(campaign.metadata.rewardToken).safeTransfer(
            msg.sender,
            finalReward
        );
        campaign.totalRewardAllocated += finalReward;

        emit RewardsClaimed(_campaignId, msg.sender, finalReward);
    }

    function withdrawStakedTokens(uint256 _campaignId) external nonReentrant {
        Campaign storage campaign = campaigns[_campaignId];
        require(
            block.timestamp > campaign.metadata.endTime,
            "Campaign has not ended"
        );
        require(
            campaign.userTotalStaked[msg.sender] > 0,
            "No tokens to withdraw"
        );

        address stakedTokenAddress = campaign.metadata.stakingToken;
        uint256 totalStaked = campaign.userTotalStaked[msg.sender];

        IERC20(stakedTokenAddress).safeTransfer(msg.sender, totalStaked);

        campaign.userTotalStaked[msg.sender] = 0;

        emit TokensReturned(_campaignId, msg.sender);
    }

    function claimUnclaimedRewards(
        uint256 _campaignId
    ) external onlyOwner nonReentrant {
        Campaign storage campaign = campaigns[_campaignId];
        require(
            block.timestamp > campaign.metadata.rewardClaimEnd,
            "Reward claim period has not ended"
        );

        uint256 unclaimedRewards = campaign.metadata.unclaimedRewards;

        IERC20(campaign.metadata.rewardToken).safeTransfer(
            owner(),
            unclaimedRewards
        );

        campaign.metadata.unclaimedRewards = 0;
        emit UnclaimedRewardsClaimed(_campaignId, unclaimedRewards);
    }

    function getCampaignBasicMetadata(
        uint256 _campaignId
    )
        external
        view
        returns (
            address rewardToken,
            uint256 startTime,
            uint256 endTime,
            uint256 rewardClaimEnd,
            uint256 totalRewards,
            uint256 unclaimedRewards,
            uint256 rewardCoefficient,
            uint256 totalWeight,
            uint256 totalRewardAllocated
        )
    {
        Campaign storage campaign = campaigns[_campaignId];
        CampaignMetadata storage metadata = campaign.metadata;
        return (
            metadata.rewardToken,
            metadata.startTime,
            metadata.endTime,
            metadata.rewardClaimEnd,
            metadata.totalRewards,
            metadata.unclaimedRewards,
            campaign.rewardCoefficient,
            campaign.totalWeight,
            campaign.totalRewardAllocated
        );
    }

    function getCampaignStakedToken(
        uint256 _campaignId
    ) external view returns (address stakedTokenAddress) {
        Campaign storage campaign = campaigns[_campaignId];
        return campaign.metadata.stakingToken;
    }

    function getCampaignTotalStaked(
        uint256 _campaignId
    ) external view returns (uint256 totalStaked) {
        Campaign storage campaign = campaigns[_campaignId];
        return campaign.totalStaked;
    }

    function getUserAccumulatedRewardWeight(
        uint256 _campaignId,
        address _user
    ) external view returns (uint256) {
        Campaign storage campaign = campaigns[_campaignId];
        return campaign.userAccumulatedRewardWeight[_user];
    }

    function getTotalWeight(
        uint256 _campaignId
    ) external view returns (uint256) {
        Campaign storage campaign = campaigns[_campaignId];
        return campaign.totalWeight;
    }
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint) external;
}
