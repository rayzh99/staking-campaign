// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../test/mocks/MockERC20.sol";
import "../src/StakingCampaign.sol";

contract MultiTokenStakingCampaignTest is Test {
    MultiTokenStakingCampaign campaignContract;
    MockERC20 public rewardToken;
    MockERC20 public stakeToken;
    Helper public helper;
    address public owner = address(0x123);
    address public user1 = address(0x456);
    address public user2 = address(0x789);

    function setUp() public {
        rewardToken = new MockERC20(1000000, "RewardToken", 18, "RTK");
        stakeToken = new MockERC20(1000000, "StakeToken", 18, "STK");
        campaignContract = new MultiTokenStakingCampaign(owner, address(0));

        rewardToken.transfer(owner, 1000);
        stakeToken.transfer(user1, 100000);
        stakeToken.transfer(user2, 100000);

        vm.startPrank(owner);
        rewardToken.approve(address(campaignContract), 1000);
        vm.stopPrank();

        helper = new Helper(campaignContract);
    }

    function testCreateCampaign() public {
        vm.startPrank(owner);
        campaignContract.createCampaign(
            address(rewardToken),
            block.timestamp + 1 hours,
            block.timestamp + 2 hours,
            block.timestamp + 3 hours,
            100,
            1000
        );
        vm.stopPrank();

        (
            address rewardTokenAddress,
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
        ) = campaignContract.getCampaignBasicMetadata(0);

        assertEq(rewardTokenAddress, address(rewardToken));
        assertEq(startTime, block.timestamp + 1 hours);
        assertEq(endTime, block.timestamp + 2 hours);
        assertEq(rewardClaimEnd, block.timestamp + 3 hours);
        assertEq(totalRewards, 100);
        assertEq(accumulatedStakeTime, 0);
        assertEq(unclaimedRewards, 100);
        assertEq(rewardCoefficient, 1 * 10 ** 18);
        assertEq(stakingTarget, 1000);
        assertEq(totalStakeCount, 0);
        assertEq(totalWeight, 0);
        assertEq(totalRewardAllocated, 0);
    }

    function createLongCampaign() public {
        vm.startPrank(owner);
        campaignContract.createCampaign(
            address(rewardToken),
            block.timestamp + 1 hours,
            block.timestamp + 1 * 28800 hours + 1 hours,
            block.timestamp + 1 * 28800 hours + 2 hours,
            100,
            1000
        );
        vm.stopPrank();

        (
            address rewardTokenAddress,
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
        ) = campaignContract.getCampaignBasicMetadata(0);

        assertEq(rewardTokenAddress, address(rewardToken));
        assertEq(startTime, block.timestamp + 1 hours);
        assertEq(endTime, block.timestamp + 1 * 28800 hours + 1 hours);
        assertEq(rewardClaimEnd, block.timestamp + 1 * 28800 hours + 2 hours);
        assertEq(totalRewards, 100);
        assertEq(accumulatedStakeTime, 0);
        assertEq(unclaimedRewards, 100);
        assertEq(rewardCoefficient, 1 * 10 ** 18);
        assertEq(stakingTarget, 1000);
        assertEq(totalStakeCount, 0);
        assertEq(totalWeight, 0);
        assertEq(totalRewardAllocated, 0);
    }

    // almost equal split the rewards
    function testSingleUserMultipleStakes() public {
        testCreateCampaign();
        vm.warp(block.timestamp + 1 hours + 1 seconds);

        // the first stake
        vm.startPrank(user1);
        stakeToken.approve(address(campaignContract), 500);
        campaignContract.stakeTokens(0, address(stakeToken), 500);
        vm.stopPrank();

        // elapsed time
        vm.warp(block.timestamp + 10 seconds);

        // the second stake
        vm.startPrank(user1);
        stakeToken.approve(address(campaignContract), 300);
        campaignContract.stakeTokens(0, address(stakeToken), 300);
        vm.stopPrank();

        (, , , , , , , , , , uint256 totalWeight, ) = campaignContract
            .getCampaignBasicMetadata(0);

        uint256 expectedTotalWeight = campaignContract.calculateRewardWeight(
            500,
            1 hours
        ) + campaignContract.calculateRewardWeight(300, 1 hours);
        approximatelyEqual(
            totalWeight,
            expectedTotalWeight,
            expectedTotalWeight / 100
        );

        address stakedTokenAddress = campaignContract.getCampaignStakedToken(
            0,
            user1
        );
        uint256 totalStaked = campaignContract.getCampaignTotalStaked(0, user1);
        assertEq(totalStaked, 800);
        assertEq(stakedTokenAddress, address(stakeToken));
    }

    function testMultipleUserStakeTokens() public {
        testCreateCampaign();
        vm.warp(block.timestamp + 1 hours + 1 seconds);

        // user1 stake
        vm.startPrank(user1);
        stakeToken.approve(address(campaignContract), 500);
        campaignContract.stakeTokens(0, address(stakeToken), 500);
        vm.stopPrank();

        // user2 stake
        vm.startPrank(user2);
        stakeToken.approve(address(campaignContract), 500);
        campaignContract.stakeTokens(0, address(stakeToken), 500);
        vm.stopPrank();

        // get weight
        (, , , , , , , , , , uint256 totalWeight, ) = campaignContract
            .getCampaignBasicMetadata(0);

        uint256 expectedTotalWeight = campaignContract.calculateRewardWeight(
            500,
            1 hours
        ) * 2;
        approximatelyEqual(totalWeight, expectedTotalWeight, 10);

        address stakedTokenAddress = campaignContract.getCampaignStakedToken(
            0,
            user1
        );
        uint256 totalStaked = campaignContract.getCampaignTotalStaked(0, user1);
        assertEq(totalStaked, 500 * 2);
        assertEq(stakedTokenAddress, address(stakeToken));
    }

    function testSettleRewards() public {
        testMultipleUserStakeTokens();
        vm.warp(block.timestamp + 1 hours);
        vm.startPrank(owner);
        campaignContract.settleRewards(0);
        vm.stopPrank();

        (
            ,
            ,
            ,
            ,
            ,
            ,
            uint256 unclaimedRewards,
            uint256 rewardCoefficient,
            ,
            ,
            ,
        ) = campaignContract.getCampaignBasicMetadata(0);

        assertEq(
            rewardCoefficient > 0,
            true,
            "Reward coefficient should be greater than 0"
        );

        uint256 expectedUnclaimedRewards = 100;
        assertEq(unclaimedRewards, expectedUnclaimedRewards);
    }

    function testClaimRewards() public {
        testSettleRewards();
        vm.warp(block.timestamp + 10 seconds);

        uint256 totalRewards = 100;
        uint256 user1StakedAmount = 500;
        uint256 user2StakedAmount = 500;
        uint256 totalStaked = user1StakedAmount + user2StakedAmount;
        uint256 expectedRewardUser1 = (totalRewards * user1StakedAmount) /
            totalStaked;
        uint256 expectedRewardUser2 = (totalRewards * user2StakedAmount) /
            totalStaked;

        vm.startPrank(user1);
        uint256 initialRewardBalance1 = rewardToken.balanceOf(user1);
        campaignContract.claimRewards(0);
        uint256 finalRewardBalance1 = rewardToken.balanceOf(user1);
        uint256 claimedRewardUser1 = finalRewardBalance1 -
            initialRewardBalance1;
        console.log("User1 Initial Reward Balance: %s", initialRewardBalance1);
        console.log("User1 Final Reward Balance: %s", finalRewardBalance1);
        console.log("expectedRewardUser1: %s", expectedRewardUser1);
        assertEq(
            approximatelyEqual(claimedRewardUser1, expectedRewardUser1, 1),
            true,
            "User1 should receive the correct amount of rewards"
        );
        vm.stopPrank();
        console.log("User1 Initial Reward Balance: %s", initialRewardBalance1);
        console.log("User1 Final Reward Balance: %s", finalRewardBalance1);
        console.log("User1 Claimed Reward: %s", claimedRewardUser1);

        vm.startPrank(user2);
        uint256 initialRewardBalance2 = rewardToken.balanceOf(user2);
        campaignContract.claimRewards(0);
        uint256 finalRewardBalance2 = rewardToken.balanceOf(user2);
        uint256 claimedRewardUser2 = finalRewardBalance2 -
            initialRewardBalance2;
        assertEq(
            claimedRewardUser2 >= expectedRewardUser2,
            true,
            "User2 should receive the correct amount of rewards"
        );
        vm.stopPrank();
        console.log("User2 Initial Reward Balance: %s", initialRewardBalance2);
        console.log("User2 Final Reward Balance: %s", finalRewardBalance2);
        console.log("User2 Claimed Reward: %s", claimedRewardUser2);

        (
            ,
            ,
            ,
            ,
            ,
            ,
            uint256 unclaimedRewards,
            uint256 rewardCoefficient,
            ,
            uint256 totalStakeCount,
            uint256 totalWeight,
            uint256 totalRewardAllocated
        ) = campaignContract.getCampaignBasicMetadata(0);
        assertEq(
            rewardCoefficient > 0,
            true,
            "Reward coefficient should be greater than 0"
        );

        console.log("Total Unclaimed Rewards: %s", unclaimedRewards);
        console.log("Reward Coefficient: %s", rewardCoefficient);
        console.log("Total Stake Count: %s", totalStakeCount);
        console.log("Total Weight: %s", totalWeight);
        console.log("Total Reward Allocated: %s", totalRewardAllocated);
    }

    function testClaimUnclaimedRewards() public {
        testCreateCampaign();
        vm.warp(block.timestamp + 1 hours + 1 seconds);

        vm.startPrank(user1);
        stakeToken.approve(address(campaignContract), 500);
        campaignContract.stakeTokens(0, address(stakeToken), 500);
        vm.stopPrank();

        vm.warp(block.timestamp + 1.5 hours + 1 seconds);
        vm.startPrank(owner);
        campaignContract.settleRewards(0);
        vm.stopPrank();

        vm.startPrank(user1);
        campaignContract.claimRewards(0);
        vm.stopPrank();

        vm.startPrank(owner);
        campaignContract.settleRewards(0);
        vm.stopPrank();

        (
            ,
            ,
            ,
            ,
            ,
            ,
            uint256 unclaimedRewardsBefore,
            uint256 rewardCoefficientBefore,
            ,
            ,
            ,
            uint256 totalRewardAllocatedBefore
        ) = campaignContract.getCampaignBasicMetadata(0);

        assertEq(
            rewardCoefficientBefore > 0,
            true,
            "Reward coefficient should be greater than 0"
        );

        vm.warp(block.timestamp + 2.5 hours + 1 seconds);

        uint256 claimedRewardUser1 = rewardToken.balanceOf(user1);

        vm.startPrank(owner);
        campaignContract.claimUnclaimedRewards(0);
        vm.stopPrank();

        (
            ,
            ,
            ,
            ,
            uint256 totalRewards,
            ,
            uint256 unclaimedRewardsAfter,
            uint256 rewardCoefficientAfter,
            ,
            ,
            ,
            uint256 totalRewardAllocatedAfter
        ) = campaignContract.getCampaignBasicMetadata(0);

        assertEq(
            unclaimedRewardsAfter,
            0,
            "All unclaimed rewards should be claimed"
        );
        assertEq(
            totalRewardAllocatedAfter,
            totalRewards - claimedRewardUser1 - unclaimedRewardsBefore
        );

        console.log("Unclaimed Rewards Before: %s", unclaimedRewardsBefore);
        console.log("Reward Coefficient Before: %s", rewardCoefficientBefore);
        console.log(
            "Total Reward Allocated Before: %s",
            totalRewardAllocatedBefore
        );
        console.log("Claimed Reward User1: %s", claimedRewardUser1);
        console.log("Unclaimed Rewards After: %s", unclaimedRewardsAfter);
        console.log("Reward Coefficient After: %s", rewardCoefficientAfter);
        console.log(
            "Total Reward Allocated After: %s",
            totalRewardAllocatedAfter
        );
    }

    function approximatelyEqual(
        uint256 a,
        uint256 b,
        uint256 tolerance
    ) internal pure returns (bool) {
        return (a > b ? a - b : b - a) <= tolerance;
    }

    // user1 take most of the rewards while user2 take the least
    function testRewardDistributionByWeight() public {
        testCreateCampaign();
        vm.warp(block.timestamp + 1 hours + 1 seconds);

        vm.startPrank(user1);
        stakeToken.approve(address(campaignContract), 10000);
        campaignContract.stakeTokens(0, address(stakeToken), 10000);
        vm.stopPrank();

        vm.warp(block.timestamp + 30 minutes);

        vm.startPrank(user2);
        stakeToken.approve(address(campaignContract), 500);
        campaignContract.stakeTokens(0, address(stakeToken), 500);
        vm.stopPrank();

        // kill time
        vm.warp(block.timestamp + 0.5 hours + 1 seconds);

        vm.startPrank(owner);
        campaignContract.settleRewards(0);
        vm.stopPrank();

        uint256 user1Weight = campaignContract.getUserAccumulatedRewardWeight(
            0,
            user1
        );
        uint256 user2Weight = campaignContract.getUserAccumulatedRewardWeight(
            0,
            user2
        );
        uint256 totalWeight = campaignContract.getTotalWeight(0);

        console.log("Post-Settlement User1 Weight: %s", user1Weight);
        console.log("Post-Settlement User2 Weight: %s", user2Weight);
        console.log("Post-Settlement Total Weight: %s", totalWeight);

        (
            ,
            ,
            ,
            ,
            ,
            ,
            uint256 unclaimedRewards,
            uint256 rewardCoefficient,
            ,
            ,
            ,
            uint256 totalRewardAllocated
        ) = campaignContract.getCampaignBasicMetadata(0);

        assertEq(
            rewardCoefficient > 0,
            true,
            "Reward coefficient should be greater than 0"
        );

        uint256 totalRewards = 100;
        uint256 user1StakedAmount = 10000;
        uint256 user2StakedAmount = 500;
        uint256 user1StakeDuration = 2 hours;
        uint256 user2StakeDuration = 30 minutes;

        user1Weight = campaignContract.calculateRewardWeight(
            user1StakedAmount,
            user1StakeDuration
        );
        user2Weight = campaignContract.calculateRewardWeight(
            user2StakedAmount,
            user2StakeDuration
        );
        totalWeight = user1Weight + user2Weight;

        console.log("User1 Weight: %s", user1Weight);
        console.log("User2 Weight: %s", user2Weight);
        console.log("Total Weight: %s", totalWeight);

        uint256 expectedRewardUser1 = (totalRewards * user1Weight) /
            totalWeight;
        uint256 expectedRewardUser2 = (totalRewards * user2Weight) /
            totalWeight;

        console.log("Expected Reward User1: %s", expectedRewardUser1);
        console.log("Expected Reward User2: %s", expectedRewardUser2);

        vm.startPrank(user1);
        uint256 initialRewardBalance1 = rewardToken.balanceOf(user1);
        console.log("Initial Reward Balance User1: %s", initialRewardBalance1);
        campaignContract.claimRewards(0);
        uint256 finalRewardBalance1 = rewardToken.balanceOf(user1);
        uint256 claimedRewardUser1 = finalRewardBalance1 -
            initialRewardBalance1;
        assertTrue(
            approximatelyEqual(claimedRewardUser1, expectedRewardUser1, 1),
            "User1 should receive the correct amount of rewards based on weight"
        );
        console.log("Final Reward Balance User1: %s", finalRewardBalance1);
        console.log("Claimed Reward User1: %s", claimedRewardUser1);
        vm.stopPrank();

        vm.startPrank(user2);
        uint256 initialRewardBalance2 = rewardToken.balanceOf(user2);
        console.log("Initial Reward Balance User2: %s", initialRewardBalance2);
        campaignContract.claimRewards(0);
        uint256 finalRewardBalance2 = rewardToken.balanceOf(user2);
        uint256 claimedRewardUser2 = finalRewardBalance2 -
            initialRewardBalance2;
        assertTrue(
            approximatelyEqual(claimedRewardUser2, expectedRewardUser2, 1),
            "User2 should receive the correct amount of rewards based on weight"
        );
        console.log("Final Reward Balance User2: %s", finalRewardBalance2);
        console.log("Claimed Reward User2: %s", claimedRewardUser2);
        vm.stopPrank();

        console.log("User1 Claimed Reward: %s", claimedRewardUser1);
        console.log("User2 Claimed Reward: %s", claimedRewardUser2);

        console.log("Total Unclaimed Rewards: %s", unclaimedRewards);
        console.log("Reward Coefficient: %s", rewardCoefficient);
        console.log("Total Reward Allocated: %s", totalRewardAllocated);
    }

    function testWithdrawStakedTokens() public {
        testClaimRewards();

        vm.warp(block.timestamp + 1 seconds);
        vm.startPrank(user1);
        uint256 initialStakeBalance1 = stakeToken.balanceOf(user1);
        console.log("Initial Stake Balance 1:", initialStakeBalance1);
        campaignContract.withdrawStakedTokens(0);
        uint256 finalStakeBalance1 = stakeToken.balanceOf(user1);
        assertEq(finalStakeBalance1, 100000);
        vm.stopPrank();

        vm.startPrank(user2);
        uint256 finalStakeBalance2Before = stakeToken.balanceOf(user2);
        console.log(
            "User2 Stake Balance Before Withdraw:",
            finalStakeBalance2Before
        );
        campaignContract.withdrawStakedTokens(0);
        uint256 finalStakeBalance2 = stakeToken.balanceOf(user2);
        assertEq(finalStakeBalance2, 100000);
        vm.stopPrank();
    }
}

contract Helper {
    MultiTokenStakingCampaign campaignContract;

    constructor(MultiTokenStakingCampaign _campaignContract) {
        campaignContract = _campaignContract;
    }

    function whoCalled() public view returns (address) {
        return msg.sender;
    }

    function printCampaignMetadata(
        uint256 _campaignId,
        address _user
    ) public view {
        (
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
        ) = campaignContract.getCampaignBasicMetadata(_campaignId);

        address stakedTokenAddress = campaignContract.getCampaignStakedToken(
            _campaignId,
            _user
        );
        uint256 totalStaked = campaignContract.getCampaignTotalStaked(
            _campaignId,
            _user
        );

        console.log("Reward Token: %s", rewardToken);
        console.log("Start Time: %s", startTime);
        console.log("End Time: %s", endTime);
        console.log("Reward Claim End: %s", rewardClaimEnd);
        console.log("Total Rewards: %s", totalRewards);
        console.log("Accumulated Stake Time: %s", accumulatedStakeTime);
        console.log("Unclaimed Rewards: %s", unclaimedRewards);
        console.log("Reward Coefficient: %s", rewardCoefficient);
        console.log("Staking Target: %s", stakingTarget);
        console.log("Total Stake Count: %s", totalStakeCount);
        console.log("Total Weight: %s", totalWeight);
        console.log("Total Reward Allocated: %s", totalRewardAllocated);
        console.log("Staked Token Address: %s", stakedTokenAddress);
        console.log("Total Staked: %s", totalStaked);
    }
}
