// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

contract StakingCampaign is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Campaign {
        address rewardToken;
        uint256 startTime;
        uint256 endTime;
        uint256 rewardClaimEnd;
        uint256 totalStaked;
        uint256 totalRewards;
        mapping(address => uint256) stakes;
        mapping(address => uint256) rewardClaims;
        address[] stakeholders;
        mapping(address => bool) hasStaked;
    }

    Campaign[] public campaigns;

    constructor(address initialOwner) Ownable(initialOwner) {}

    event CampaignCreated(uint256 campaignId, address rewardToken, uint256 startTime, uint256 endTime, uint256 rewardClaimEnd, uint256 totalRewards);
    event TokensStaked(uint256 campaignId, address staker, uint256 amount);
    event RewardsClaimed(uint256 campaignId, address staker, uint256 reward);
    event UnclaimedRewardsClaimed(uint256 campaignId, uint256 amount);

    function createCampaign(
        address _rewardToken,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _rewardClaimEnd,
        uint256 _totalRewards
    ) external onlyOwner {
        campaigns.push();
        Campaign storage newCampaign = campaigns[campaigns.length - 1];
        newCampaign.rewardToken = _rewardToken;
        newCampaign.startTime = _startTime;
        newCampaign.endTime = _endTime;
        newCampaign.rewardClaimEnd = _rewardClaimEnd;
        newCampaign.totalStaked = 0;
        newCampaign.totalRewards = _totalRewards;

        emit CampaignCreated(campaigns.length - 1, _rewardToken, _startTime, _endTime, _rewardClaimEnd, _totalRewards);
    }

    function stakeTokens(uint256 _campaignId, uint256 _amount) external nonReentrant {
        Campaign storage campaign = campaigns[_campaignId];
        require(block.timestamp >= campaign.startTime, "Campaign has not started");
        require(block.timestamp <= campaign.endTime, "Campaign has ended");

        IERC20(campaign.rewardToken).safeTransferFrom(msg.sender, address(this), _amount);
        campaign.stakes[msg.sender] += _amount;
        campaign.totalStaked += _amount;

        if (!campaign.hasStaked[msg.sender]) {
            campaign.stakeholders.push(msg.sender);
            campaign.hasStaked[msg.sender] = true;
        }

        emit TokensStaked(_campaignId, msg.sender, _amount);
    }

    function claimRewards(uint256 _campaignId) external nonReentrant {
        Campaign storage campaign = campaigns[_campaignId];
        require(block.timestamp > campaign.endTime, "Campaign has not ended");
        require(block.timestamp <= campaign.rewardClaimEnd, "Reward claim period has ended");

        uint256 stake = campaign.stakes[msg.sender];
        require(stake > 0, "No stake found for user");

        uint256 reward = (stake * campaign.totalRewards) / campaign.totalStaked;
        IERC20(campaign.rewardToken).safeTransfer(msg.sender, reward);
        campaign.rewardClaims[msg.sender] += reward;
        campaign.stakes[msg.sender] = 0;

        emit RewardsClaimed(_campaignId, msg.sender, reward);
    }

    function claimUnclaimedRewards(uint256 _campaignId) external onlyOwner nonReentrant {
        Campaign storage campaign = campaigns[_campaignId];
        require(block.timestamp > campaign.rewardClaimEnd, "Reward claim period has not ended");

        uint256 unclaimedRewards = campaign.totalRewards;
        for (uint256 i = 0; i < campaign.stakeholders.length; i++) {
            address stakeholder = campaign.stakeholders[i];
            unclaimedRewards -= campaign.rewardClaims[stakeholder];
        }

        IERC20(campaign.rewardToken).safeTransfer(owner(), unclaimedRewards);

        emit UnclaimedRewardsClaimed(_campaignId, unclaimedRewards);
    }
}