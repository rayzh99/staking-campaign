// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "lib/forge-std/src/console.sol";

contract MultiTokenStakingCampaign is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    struct CampaignMetadata {
        address rewardToken;
        uint256 startTime;
        uint256 endTime;
        uint256 rewardClaimEnd;
        uint256 totalRewards;
        uint256 accumulatedStakeTime;
        uint256 unclaimedRewards;
        mapping(address => uint256) totalStaked;
    }

    struct UserStakeInfo {
        uint256 amount;
        uint256 startTime;
        uint256 rewardWeight;
        uint256 pendingReward;
        address tokenAddress;
    }

    struct Campaign {
        CampaignMetadata metadata;
        mapping(address => UserStakeInfo[]) userStakes;
        mapping(address => uint256) userPendingRewards;
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
        uint256 _totalRewards
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
        newCampaign.metadata.accumulatedStakeTime = 0;
        newCampaign.metadata.unclaimedRewards = _totalRewards;

        emit CampaignCreated(
            campaigns.length - 1,
            _startTime,
            _endTime,
            _rewardClaimEnd,
            _totalRewards
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
        uint256 rewardWeight = _amount * stakingDuration;
        uint256 pendingReward = (rewardWeight * campaign.metadata.totalRewards) / campaign.metadata.accumulatedStakeTime;
        campaign.userPendingRewards[msg.sender] += pendingReward;
        campaign.metadata.unclaimedRewards -= pendingReward;
        campaign.metadata.totalStaked[_tokenAddress] += _amount;
        // token price not considered here
        campaign.metadata.accumulatedStakeTime += rewardWeight;

        UserStakeInfo memory userStake;
        userStake.amount = _amount;
        userStake.startTime = block.timestamp;
        userStake.tokenAddress = _tokenAddress;
        userStake.rewardWeight = rewardWeight;
        campaign.userStakes[msg.sender].push(userStake);

        emit TokensStaked(_campaignId, msg.sender, _tokenAddress, _amount);
        console.log("User address:", msg.sender);
        console.log("Staked amount:", _amount);
        console.log("Token address:", _tokenAddress);
        console.log("Campaign ID:", _campaignId);
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

        UserStakeInfo[] storage userStakes = campaign.userStakes[msg.sender];
        require(userStakes.length > 0, "No staked tokens found");
        for (uint256 i = 0; i < userStakes.length; i++) {
            UserStakeInfo storage userStake = userStakes[i];

            IERC20(userStake.tokenAddress).safeTransfer(
                msg.sender,
                userStake.amount
            );

            delete campaign.userStakes[msg.sender][i];
        }
        emit TokensReturned(_campaignId, msg.sender);
        
        uint256 reward = campaign.userPendingRewards[msg.sender];
        require(reward > 0, "No rewards to claim");
        IERC20(campaign.metadata.rewardToken).safeTransfer(msg.sender, reward);
        campaign.userPendingRewards[msg.sender] = 0;
        emit RewardsClaimed(_campaignId, msg.sender, reward);

        console.log("User address:", msg.sender);
        console.log("Claimed reward:", reward);
        console.log("Campaign ID:", _campaignId);
    }

    function claimUnclaimedRewards(uint256 _campaignId) external onlyOwner nonReentrant {
        Campaign storage campaign = campaigns[_campaignId];
        require(block.timestamp > campaign.metadata.rewardClaimEnd, "Reward claim period has not ended");

        uint256 unclaimedRewards = campaign.metadata.unclaimedRewards; // 使用记录的未领取奖励

        IERC20(campaign.metadata.rewardToken).safeTransfer(owner(), unclaimedRewards);
        emit UnclaimedRewardsClaimed(_campaignId, unclaimedRewards);
        console.log("Owner claimed unclaimed rewards:", unclaimedRewards);
        console.log("Campaign ID:", _campaignId);
    }

    function getCampaignMetadata(
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
            uint256 accumulatedStakeTime
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
            metadata.accumulatedStakeTime
        );
    }
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint) external;
}
