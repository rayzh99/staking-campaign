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
        uint256 accumulatedStakeTime;
        uint256 unclaimedRewards;
        uint256 rewardCoefficient;
        uint256 stakingTarget;
        mapping(address => uint256) totalStaked;
    }

    struct Campaign {
        CampaignMetadata metadata;
        mapping(address => uint256) userStakeCount;
        mapping(address => address) userStakedToken;
        mapping(address => uint256) userTotalStaked;
        mapping(address => uint256) userAccumulatedRewardWeight;
        mapping(address => uint256) userPendingRewards;
        uint256 totalStakeCount;
        uint256 totalWeight;
        uint256 totalRewardAllocated;
        address[] stakeholders;
        mapping(address => bool) hasStaked;
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
        uint256 totalRewards,
        uint256 stakingTarget
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
    event RewardsSettled(uint256 campaignId);

    function createCampaign(
        address _rewardToken,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _rewardClaimEnd,
        uint256 _totalRewards,
        uint256 _stakingTarget
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
        console.log(
            "newCampaign.metadata.rewardClaimEnd",
            newCampaign.metadata.rewardClaimEnd
        );
        newCampaign.metadata.totalRewards = _totalRewards;
        newCampaign.metadata.accumulatedStakeTime = 0;
        newCampaign.metadata.unclaimedRewards = _totalRewards;
        newCampaign.metadata.rewardCoefficient = SCALE_FACTOR;
        newCampaign.metadata.stakingTarget = _stakingTarget > 0
            ? _stakingTarget
            : 0;

        emit CampaignCreated(
            campaigns.length - 1,
            _startTime,
            _endTime,
            _rewardClaimEnd,
            _totalRewards,
            _stakingTarget
        );
        console.log("Campaign created with ID:", campaigns.length - 1);
    }

    function stakeTokens(
        uint256 _campaignId,
        address _tokenAddress,
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
        if (_tokenAddress == WETH) {
            require(msg.value == _amount, "Incorrect ETH amount sent");
            IWETH(WETH).deposit{value: _amount}();
            IERC20(WETH).safeTransferFrom(
                address(this),
                address(this),
                _amount
            );
        } else {
            IERC20(_tokenAddress).safeTransferFrom(
                msg.sender,
                address(this),
                _amount
            );
        }

        if (!campaign.hasStaked[msg.sender]) {
            campaign.stakeholders.push(msg.sender);
            campaign.hasStaked[msg.sender] = true;
        }

        uint256 stakingDuration = campaign.metadata.endTime - block.timestamp;
        require(stakingDuration > 0, "Invalid staking duration");
        require(_amount > 0, "Invalid staking amount");

        campaign.metadata.accumulatedStakeTime += stakingDuration;

        campaign.userStakeCount[msg.sender]++;
        campaign.totalStakeCount++;

        uint256 rewardWeight = calculateRewardWeight(_amount, stakingDuration);

        campaign.totalWeight += rewardWeight;
        campaign.userAccumulatedRewardWeight[msg.sender] += rewardWeight;

        campaign.userTotalStaked[msg.sender] += _amount;
        campaign.metadata.totalStaked[_tokenAddress] += _amount;
        campaign.userStakedToken[msg.sender] = _tokenAddress;

        uint256 estimatedReward = calculateReward(
            rewardWeight,
            campaign.metadata.totalRewards,
            campaign.totalWeight
        );
        campaign.userPendingRewards[msg.sender] += estimatedReward;

        emit TokensStaked(_campaignId, msg.sender, _tokenAddress, _amount);
    }

    function calculateRewardWeight(
        uint256 amount,
        uint256 duration
    ) public pure returns (uint256) {
        uint256 weight = amount * duration;
        uint256 maxWeight = 10000;
        uint256 scaledWeight = ((weight * 98) / maxWeight) + 1;
        console.log("scaledWeight", scaledWeight);
        return scaledWeight;
    }

    function calculateReward(
        uint256 rewardWeight,
        uint256 totalRewards,
        uint256 totalWeight
    ) internal pure returns (uint256) {
        require(totalWeight > 0, "Total weight must be greater than zero");
        uint256 reward = (rewardWeight * totalRewards) / totalWeight;
        return reward;
    }

    function calculateFinalReward(
        uint256 userWeight,
        uint256 rewardCoefficient
    ) internal pure returns (uint256) {
        console.log("userWeight", userWeight);
        console.log("rewardCoefficient", rewardCoefficient);
        return (userWeight * rewardCoefficient) / SCALE_FACTOR;
    }

    function claimRewards(uint256 _campaignId) external nonReentrant {
        Campaign storage campaign = campaigns[_campaignId];
        require(
            block.timestamp > campaign.metadata.endTime,
            "Campaign has not ended"
        );
        console.log("block timestamp", block.timestamp);
        console.log(
            "campaign.metadata.rewardClaimEnd",
            campaign.metadata.rewardClaimEnd
        );
        require(
            block.timestamp <= campaign.metadata.rewardClaimEnd,
            "Reward claim period has ended"
        );
        uint256 userWeight = campaign.userAccumulatedRewardWeight[msg.sender];
        require(userWeight > 0, "No rewards to claim");

        uint256 finalReward = calculateFinalReward(
            userWeight,
            campaign.metadata.rewardCoefficient
        );
        campaign.userPendingRewards[msg.sender] = 0;
        console.log(
            "campaign.metadata.unclaimedRewards",
            campaign.metadata.unclaimedRewards
        );
        console.log("finalReward", finalReward);
        console.log(campaign.metadata.unclaimedRewards);
        console.log(finalReward);
        campaign.metadata.unclaimedRewards -= finalReward;
        campaign.totalWeight -= userWeight;
        campaign.userAccumulatedRewardWeight[msg.sender] = 0;

        IERC20(campaign.metadata.rewardToken).safeTransfer(
            msg.sender,
            finalReward
        );

        emit RewardsClaimed(_campaignId, msg.sender, finalReward);
        uint256 remainingRewards = campaign.metadata.unclaimedRewards;

        uint256 remainingWeight = campaign.totalWeight;
        console.log("remainingWeight", remainingWeight);
        console.log("remainingRewards", remainingRewards);
        if (remainingWeight > 0) {
            campaign.metadata.rewardCoefficient =
                (remainingRewards * SCALE_FACTOR) /
                remainingWeight;
        }
    }

    function withdrawStakedTokens(uint256 _campaignId) external nonReentrant {
        Campaign storage campaign = campaigns[_campaignId];
        require(
            block.timestamp > campaign.metadata.endTime,
            "Campaign has not ended"
        );
        require(campaign.hasStaked[msg.sender], "No tokens to withdraw");

        address stakedTokenAddress = campaign.userStakedToken[msg.sender];
        uint256 totalStaked = campaign.userTotalStaked[msg.sender];

        require(totalStaked > 0, "No tokens to withdraw");

        IERC20(stakedTokenAddress).safeTransfer(msg.sender, totalStaked);

        campaign.userTotalStaked[msg.sender] = 0;
        campaign.hasStaked[msg.sender] = false;
        campaign.userStakedToken[msg.sender] = address(0);

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

    function settleRewards(uint256 _campaignId) external onlyOwner {
        Campaign storage campaign = campaigns[_campaignId];
        require(
            block.timestamp > campaign.metadata.endTime,
            "Campaign has not ended"
        );

        campaign.metadata.rewardCoefficient =
            (campaign.metadata.totalRewards * SCALE_FACTOR) /
            (campaign.totalWeight == 0 ? 1 : campaign.totalWeight);

        console.log(
            "campaign.metadata.rewardCoefficient",
            campaign.metadata.rewardCoefficient
        );
        emit RewardsSettled(_campaignId);
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
            uint256 accumulatedStakeTime,
            uint256 unclaimedRewards,
            uint256 rewardCoefficient,
            uint256 stakingTarget,
            uint256 totalStakeCount,
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
            metadata.accumulatedStakeTime,
            metadata.unclaimedRewards,
            metadata.rewardCoefficient,
            metadata.stakingTarget,
            campaign.totalStakeCount,
            campaign.totalWeight,
            campaign.totalRewardAllocated
        );
    }

    function getCampaignStakedToken(
        uint256 _campaignId,
        address _user
    ) external view returns (address stakedTokenAddress) {
        Campaign storage campaign = campaigns[_campaignId];
        return campaign.userStakedToken[_user];
    }

    function getCampaignTotalStaked(
        uint256 _campaignId,
        address _user
    ) external view returns (uint256 totalStaked) {
        Campaign storage campaign = campaigns[_campaignId];
        return campaign.metadata.totalStaked[campaign.userStakedToken[_user]];
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
