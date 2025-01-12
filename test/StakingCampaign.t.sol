// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../test/mocks/MockERC20.sol";
import "../test/mocks/MockWETH.sol";
import "../src/StakingCampaign.sol";

contract MultiTokenStakingCampaignTest is Test {
    MultiTokenStakingCampaign campaignContract;
    MockERC20 public rewardToken;
    MockERC20 public stakeToken;
    MockWETH public weth;
    Helper public helper;
    address public owner = address(0x123);
    address public user1 = address(0x456);
    address public user2 = address(0x789);
    address public wethAddress = address(0xabc);

    function setUp() public {
        rewardToken = new MockERC20(1000000, "RewardToken", 18, "RTK");
        stakeToken = new MockERC20(1000000, "StakeToken", 18, "STK");
        weth = new MockWETH();
        campaignContract = new MultiTokenStakingCampaign(owner, address(weth));

        rewardToken.transfer(owner, 1000);
        stakeToken.transfer(user1, 100000);
        stakeToken.transfer(user2, 100000);

        vm.startPrank(owner);
        rewardToken.approve(address(campaignContract), 1000);
        vm.stopPrank();

        helper = new Helper(campaignContract);
    }

    function approximatelyEqual(
        uint256 a,
        uint256 b,
        uint256 tolerance
    ) internal pure returns (bool) {
        return (a > b ? a - b : b - a) <= tolerance;
    }

    function testCreateCampaign() public {
        vm.startPrank(owner);
        campaignContract.createCampaign(
            address(rewardToken),
            block.timestamp + 1 hours,
            block.timestamp + 2 hours,
            block.timestamp + 3 hours,
            100,
            address(stakeToken)
        );
        vm.stopPrank();

        (
            address rewardTokenAddress,
            uint256 startTime,
            uint256 endTime,
            uint256 rewardClaimEnd,
            uint256 totalRewards,
            uint256 unclaimedRewards,
            uint256 rewardCoefficient,
            uint256 totalWeight,
            uint256 totalRewardAllocated
        ) = campaignContract.getCampaignBasicMetadata(0);

        assertEq(rewardTokenAddress, address(rewardToken));
        assertEq(startTime, block.timestamp + 1 hours);
        assertEq(endTime, block.timestamp + 2 hours);
        assertEq(rewardClaimEnd, block.timestamp + 3 hours);
        assertEq(totalRewards, 100);
        assertEq(unclaimedRewards, 100);
        assertEq(rewardCoefficient, 1 * 10 ** 18);
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
            address(stakeToken)
        );
        vm.stopPrank();

        (
            address rewardTokenAddress,
            uint256 startTime,
            uint256 endTime,
            uint256 rewardClaimEnd,
            uint256 totalRewards,
            uint256 unclaimedRewards,
            uint256 rewardCoefficient,
            uint256 totalWeight,
            uint256 totalRewardAllocated
        ) = campaignContract.getCampaignBasicMetadata(0);

        assertEq(rewardTokenAddress, address(rewardToken));
        assertEq(startTime, block.timestamp + 1 hours);
        assertEq(endTime, block.timestamp + 1 * 28800 hours + 1 hours);
        assertEq(rewardClaimEnd, block.timestamp + 1 * 28800 hours + 2 hours);
        assertEq(totalRewards, 100);
        assertEq(unclaimedRewards, 100);
        assertEq(rewardCoefficient, 1 * 10 ** 18);
        assertEq(totalWeight, 0);
        assertEq(totalRewardAllocated, 0);
    }

    function testStakeETH() public {
        vm.startPrank(owner);
        campaignContract.createCampaign(
            address(rewardToken),
            block.timestamp + 1 hours,
            block.timestamp + 2 hours,
            block.timestamp + 3 hours,
            100,
            address(0)
        );
        vm.stopPrank();

        vm.deal(user1, 1 ether);

        vm.warp(block.timestamp + 1 hours + 1 seconds);
        vm.startPrank(user1);
        uint256 initialETHBalance = user1.balance;
        campaignContract.stakeTokens{value: 1 ether}(0, 1 ether);
        uint256 finalETHBalance = user1.balance;
        vm.stopPrank();

        assertEq(
            initialETHBalance - finalETHBalance,
            1 ether,
            "ETH should be staked"
        );

        uint256 contractWETHBalance = IERC20(campaignContract.WETH()).balanceOf(
            address(campaignContract)
        );
        assertEq(
            contractWETHBalance,
            1 ether,
            "Contract should hold 1 ETH worth of WETH"
        );

        (
            ,
            uint256 startTime,
            uint256 endTime,
            ,
            ,
            ,
            ,
            uint256 totalWeight,

        ) = campaignContract.getCampaignBasicMetadata(0);

        uint256 stakingDuration = endTime - block.timestamp;
        uint256 expectedWeight = 1 ether * stakingDuration;

        assertEq(totalWeight, expectedWeight, "Total weight should be correct");

        uint256 totalStaked = campaignContract.getCampaignTotalStaked(0);
        assertEq(totalStaked, 1 ether, "Total staked should be 1 ETH");

        (, , , , , uint256 unclaimedRewardsBefore, , , ) = campaignContract
            .getCampaignBasicMetadata(0);
        (, , , , , , uint256 rewardCoefficientBefore, , ) = campaignContract
            .getCampaignBasicMetadata(0);
        (, , , , , , , , uint256 totalRewardAllocatedBefore) = campaignContract
            .getCampaignBasicMetadata(0);

        helper.logFinalComparison(
            0,
            1 ether, // 用户质押的ETH
            0,
            1 ether, // 期望质押的ETH
            0,
            unclaimedRewardsBefore,
            totalRewardAllocatedBefore,
            rewardCoefficientBefore
        );
    }

    function testSingleUserMultipleStakes() public {
        testCreateCampaign();
        vm.warp(block.timestamp + 1 hours + 1 seconds);

        uint256 initialTimestamp = block.timestamp;
        console.log("Initial Timestamp: %s", initialTimestamp);

        uint256 initialBalance1 = stakeToken.balanceOf(user1);
        console.log(
            "User1 Initial Balance Before First Stake: %s",
            initialBalance1
        );

        // User 1 performs the first stake
        vm.startPrank(user1);
        stakeToken.approve(address(campaignContract), 500);
        campaignContract.stakeTokens(0, 500);
        uint256 firstStakeBalance = stakeToken.balanceOf(user1);
        uint256 firstStakeTimestamp = block.timestamp;
        vm.stopPrank();

        console.log("User1 Balance After First Stake: %s", firstStakeBalance);
        console.log("First Stake Timestamp: %s", firstStakeTimestamp);

        // Elapsed time
        vm.warp(firstStakeTimestamp + 10 seconds);
        uint256 afterWarpTimestamp = block.timestamp;
        console.log("After Warp Timestamp: %s", afterWarpTimestamp);

        // User 1 initial balance before second stake
        uint256 beforeSecondStakeBalance = stakeToken.balanceOf(user1);
        console.log(
            "User1 Balance Before Second Stake: %s",
            beforeSecondStakeBalance
        );

        // User 1 performs the second stake
        vm.startPrank(user1);
        stakeToken.approve(address(campaignContract), 300);
        campaignContract.stakeTokens(0, 300);
        uint256 secondStakeBalance = stakeToken.balanceOf(user1);
        uint256 secondStakeTimestamp = block.timestamp;
        vm.stopPrank();

        console.log("User1 Balance After Second Stake: %s", secondStakeBalance);
        console.log("Second Stake Timestamp: %s", secondStakeTimestamp);

        // Verify total weight and staked tokens
        (, , , , , , , uint256 totalWeight, ) = campaignContract
            .getCampaignBasicMetadata(0);

        // Calculate actual durations and total staked
        uint256 firstStakeDuration = firstStakeTimestamp - initialTimestamp;
        uint256 secondStakeDuration = secondStakeTimestamp - initialTimestamp;

        uint256 expectedTotalWeight = (500 * firstStakeDuration) +
            (300 * secondStakeDuration);
        bool weightApproximatelyEqual = approximatelyEqual(
            totalWeight / 1000,
            expectedTotalWeight,
            expectedTotalWeight / 10
        );

        console.log("Initial Timestamp (not modified): %s", initialTimestamp);
        console.log("First Stake Timestamp: %s", firstStakeTimestamp);
        console.log("Second Stake Timestamp: %s", secondStakeTimestamp);
        console.log("Expected First Stake Duration: %s", firstStakeDuration);
        console.log("Expected Second Stake Duration: %s", secondStakeDuration);
        console.log("Expected Total Weight: %s", expectedTotalWeight);
        console.log("Actual Total Weight: %s", totalWeight);
        console.log("Weight Approximately Equal: %s", weightApproximatelyEqual);

        assertTrue(
            weightApproximatelyEqual,
            "Total weight should be approximately equal to the expected total weight"
        );

        uint256 totalStaked = campaignContract.getCampaignTotalStaked(0);
        console.log("Total Staked: %s", totalStaked);
        assertEq(totalStaked, 800, "Total staked should be 800");

        (
            ,
            ,
            ,
            ,
            ,
            ,
            uint256 unclaimedRewardsBefore,
            uint256 rewardCoefficientBefore,
            uint256 totalRewardAllocatedBefore
        ) = campaignContract.getCampaignBasicMetadata(0);

        helper.logFinalComparison(
            0,
            0,
            0,
            0,
            0,
            unclaimedRewardsBefore,
            totalRewardAllocatedBefore,
            rewardCoefficientBefore
        );
    }

    function testMultipleUserStakeTokens() public {
        testCreateCampaign();
        vm.warp(block.timestamp + 1 hours + 1 seconds);

        // user1 stake
        vm.startPrank(user1);
        stakeToken.approve(address(campaignContract), 500);
        campaignContract.stakeTokens(0, 500);
        vm.stopPrank();

        // user2 stake
        vm.startPrank(user2);
        stakeToken.approve(address(campaignContract), 500);
        campaignContract.stakeTokens(0, 500);
        vm.stopPrank();

        (, , , , , , , uint256 totalWeight, ) = campaignContract
            .getCampaignBasicMetadata(0);

        uint256 expectedTotalWeight = (500 * 1 hours) * 2;
        approximatelyEqual(totalWeight, expectedTotalWeight, 10);

        uint256 totalStaked = campaignContract.getCampaignTotalStaked(0);
        assertEq(totalStaked, 500 * 2);
    }

    function testClaimRewards() public {
        testMultipleUserStakeTokens();

        vm.warp(block.timestamp + 1 hours + 1 seconds);

        uint256 totalRewards = 100;
        uint256 user1StakedAmount = 500;
        uint256 user2StakedAmount = 500;
        uint256 totalStaked = user1StakedAmount + user2StakedAmount;
        uint256 expectedRewardUser1 = (totalRewards * user1StakedAmount) /
            totalStaked;
        uint256 expectedRewardUser2 = (totalRewards * user2StakedAmount) /
            totalStaked;

        // User 1 claims rewards
        vm.startPrank(user1);
        uint256 initialRewardBalance1 = rewardToken.balanceOf(user1);
        campaignContract.claimRewards(0);
        uint256 claimedRewardUser1 = rewardToken.balanceOf(user1) -
            initialRewardBalance1;
        vm.stopPrank();

        console.log("User1 Initial Reward Balance: %s", initialRewardBalance1);
        console.log("User1 Claimed Reward: %s", claimedRewardUser1);

        assertTrue(
            approximatelyEqual(claimedRewardUser1, expectedRewardUser1, 1),
            "User1 should receive the correct amount of rewards"
        );

        // User 2 claims rewards
        vm.startPrank(user2);
        uint256 initialRewardBalance2 = rewardToken.balanceOf(user2);
        campaignContract.claimRewards(0);
        uint256 claimedRewardUser2 = rewardToken.balanceOf(user2) -
            initialRewardBalance2;
        vm.stopPrank();

        console.log("User2 Initial Reward Balance: %s", initialRewardBalance2);
        console.log("User2 Claimed Reward: %s", claimedRewardUser2);

        assertTrue(
            approximatelyEqual(claimedRewardUser2, expectedRewardUser2, 1),
            "User2 should receive the correct amount of rewards"
        );

        (, , , , , uint256 unclaimedRewardsBefore, , , ) = campaignContract
            .getCampaignBasicMetadata(0);
        (, , , , , , uint256 rewardCoefficientBefore, , ) = campaignContract
            .getCampaignBasicMetadata(0);
        (, , , , , , , , uint256 totalRewardAllocatedBefore) = campaignContract
            .getCampaignBasicMetadata(0);

        helper.logFinalComparison(
            0,
            claimedRewardUser1,
            claimedRewardUser2,
            expectedRewardUser1,
            expectedRewardUser2,
            unclaimedRewardsBefore,
            totalRewardAllocatedBefore,
            rewardCoefficientBefore
        );
    }

    function testClaimUnclaimedRewards() public {
        testCreateCampaign();
        vm.warp(block.timestamp + 1 hours + 1 seconds);

        // User 1 stakes tokens
        vm.startPrank(user1);
        stakeToken.approve(address(campaignContract), 500);
        campaignContract.stakeTokens(0, 500);
        vm.stopPrank();

        // move to claim period
        vm.warp(block.timestamp + 1.5 hours + 1 seconds);

        // User 1 claims rewards
        vm.startPrank(user1);
        campaignContract.claimRewards(0);
        vm.stopPrank();

        (
            ,
            ,
            ,
            ,
            ,
            uint256 unclaimedRewardsBefore,
            uint256 rewardCoefficientBefore,
            ,
            uint256 totalRewardAllocatedBefore
        ) = campaignContract.getCampaignBasicMetadata(0);

        assertTrue(
            rewardCoefficientBefore > 0,
            "Reward coefficient should be greater than 0"
        );

        vm.warp(block.timestamp + 2.5 hours + 1 seconds);

        uint256 claimedRewardUser1 = rewardToken.balanceOf(user1);

        vm.startPrank(owner);
        campaignContract.claimUnclaimedRewards(0);
        vm.stopPrank();

        helper.logFinalComparison(
            0,
            claimedRewardUser1,
            0,
            0,
            0,
            unclaimedRewardsBefore,
            totalRewardAllocatedBefore,
            rewardCoefficientBefore
        );
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

    function testRewardDistributionByWeight() public {
        testCreateCampaign();
        vm.warp(block.timestamp + 1 hours + 1 seconds);

        // User 1 stakes tokens
        vm.startPrank(user1);
        stakeToken.approve(address(campaignContract), 10000);
        campaignContract.stakeTokens(0, 10000);
        vm.stopPrank();

        vm.warp(block.timestamp + 30 minutes);

        // User 2 stakes tokens
        vm.startPrank(user2);
        stakeToken.approve(address(campaignContract), 500);
        campaignContract.stakeTokens(0, 500);
        vm.stopPrank();

        vm.warp(block.timestamp + 0.5 hours + 1 seconds);

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
            uint256 unclaimedRewards,
            uint256 rewardCoefficient,
            ,
            uint256 totalRewardAllocated
        ) = campaignContract.getCampaignBasicMetadata(0);

        assertTrue(
            rewardCoefficient > 0,
            "Reward coefficient should be greater than 0"
        );

        uint256 totalRewards = 100;
        user1Weight = 10000 * 2 hours;
        user2Weight = 500 * 30 minutes;
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

        // User 1 claims rewards
        vm.startPrank(user1);
        uint256 claimedRewardUser1 = rewardToken.balanceOf(user1);
        campaignContract.claimRewards(0);
        claimedRewardUser1 = rewardToken.balanceOf(user1) - claimedRewardUser1;
        assertTrue(
            approximatelyEqual(claimedRewardUser1, expectedRewardUser1, 2),
            "User1 should receive the correct amount of rewards based on weight"
        );
        console.log("Claimed Reward User1: %s", claimedRewardUser1);
        vm.stopPrank();

        // User 2 claims rewards
        vm.startPrank(user2);
        uint256 claimedRewardUser2 = rewardToken.balanceOf(user2);
        campaignContract.claimRewards(0);
        claimedRewardUser2 = rewardToken.balanceOf(user2) - claimedRewardUser2;
        assertTrue(
            approximatelyEqual(claimedRewardUser2, expectedRewardUser2, 2),
            "User2 should receive the correct amount of rewards based on weight"
        );
        console.log("Claimed Reward User2: %s", claimedRewardUser2);
        vm.stopPrank();

        console.log("User1 Claimed Reward: %s", claimedRewardUser1);
        console.log("User2 Claimed Reward: %s", claimedRewardUser2);
        console.log("Total Unclaimed Rewards: %s", unclaimedRewards);
        console.log("Reward Coefficient: %s", rewardCoefficient);
        console.log("Total Reward Allocated: %s", totalRewardAllocated);
    }

    function testEqualRewardsForDifferentStakeAndTime() public {
        testCreateCampaign();
        vm.warp(block.timestamp + 1 hours + 1 seconds);

        vm.startPrank(user1);
        stakeToken.approve(address(campaignContract), 500);
        campaignContract.stakeTokens(0, 500);
        vm.stopPrank();

        vm.warp(block.timestamp + 30 minutes);

        // User 2 stakes tokens later but with more amount
        vm.startPrank(user2);
        stakeToken.approve(address(campaignContract), 1000);
        campaignContract.stakeTokens(0, 1000);
        vm.stopPrank();

        vm.warp(block.timestamp + 30 minutes + 1 seconds);

        uint256 user1Weight = 500 * 1 hours;
        uint256 user2Weight = 1000 * 30 minutes;
        uint256 totalWeight = user1Weight + user2Weight;
        uint256 totalRewards = 100;
        uint256 expectedRewardUser1 = (totalRewards * user1Weight) /
            totalWeight;
        uint256 expectedRewardUser2 = (totalRewards * user2Weight) /
            totalWeight;

        console.log("User1 Weight: %s", user1Weight);
        console.log("User2 Weight: %s", user2Weight);
        console.log("Total Weight: %s", totalWeight);
        console.log("Expected Reward User1: %s", expectedRewardUser1);
        console.log("Expected Reward User2: %s", expectedRewardUser2);

        vm.startPrank(user1);
        uint256 claimedRewardUser1 = rewardToken.balanceOf(user1);
        campaignContract.claimRewards(0);
        claimedRewardUser1 = rewardToken.balanceOf(user1) - claimedRewardUser1;
        assertTrue(
            approximatelyEqual(claimedRewardUser1, expectedRewardUser1, 1),
            "User1 should receive the correct amount of rewards based on weight"
        );
        console.log("Claimed Reward User1: %s", claimedRewardUser1);
        vm.stopPrank();

        vm.startPrank(user2);
        uint256 claimedRewardUser2 = rewardToken.balanceOf(user2);
        campaignContract.claimRewards(0);
        claimedRewardUser2 = rewardToken.balanceOf(user2) - claimedRewardUser2;
        assertTrue(
            approximatelyEqual(claimedRewardUser2, expectedRewardUser2, 2),
            "User2 should receive the correct amount of rewards based on weight"
        );
        console.log("Claimed Reward User2: %s", claimedRewardUser2);
        vm.stopPrank();

        assertTrue(
            approximatelyEqual(claimedRewardUser1, claimedRewardUser2, 1),
            "User1 and User2 should receive equal rewards"
        );

        (
            ,
            ,
            ,
            ,
            ,
            uint256 unclaimedRewardsBefore,
            uint256 rewardCoefficientBefore,
            ,
            uint256 totalRewardAllocatedBefore
        ) = campaignContract.getCampaignBasicMetadata(0);

        helper.logFinalComparison(
            0,
            claimedRewardUser1,
            claimedRewardUser2,
            expectedRewardUser1,
            expectedRewardUser2,
            unclaimedRewardsBefore,
            totalRewardAllocatedBefore,
            rewardCoefficientBefore
        );
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

    function printCampaignMetadata(uint256 _campaignId) public view {
        (
            address rewardToken,
            uint256 startTime,
            uint256 endTime,
            uint256 rewardClaimEnd,
            uint256 totalRewards,
            uint256 unclaimedRewards,
            uint256 rewardCoefficient,
            uint256 totalWeight,
            uint256 totalRewardAllocated
        ) = campaignContract.getCampaignBasicMetadata(_campaignId);

        console.log("Reward Token: %s", rewardToken);
        console.log("Start Time: %s", startTime);
        console.log("End Time: %s", endTime);
        console.log("Reward Claim End: %s", rewardClaimEnd);
        console.log("Total Rewards: %s", totalRewards);
        console.log("Unclaimed Rewards: %s", unclaimedRewards);
        console.log("Reward Coefficient: %s", rewardCoefficient);
        console.log("Total Weight: %s", totalWeight);
        console.log("Total Reward Allocated: %s", totalRewardAllocated);
    }

    function logFinalComparison(
        uint256 _campaignId,
        uint256 claimedRewardUser1,
        uint256 claimedRewardUser2,
        uint256 expectedRewardUser1,
        uint256 expectedRewardUser2,
        uint256 unclaimedRewardsBefore,
        uint256 totalRewardAllocatedBefore,
        uint256 rewardCoefficientBefore
    ) public view {
        (
            ,
            ,
            ,
            ,
            uint256 totalRewards,
            uint256 unclaimedRewardsAfter,
            uint256 rewardCoefficientAfter,
            ,
            uint256 totalRewardAllocatedAfter
        ) = campaignContract.getCampaignBasicMetadata(_campaignId);

        uint256 remainingRewards = totalRewards - totalRewardAllocatedAfter;

        console.log("---- Final Comparison ----");
        console.log("Total Rewards: %s", totalRewards);
        console.log("Unclaimed Rewards Before: %s", unclaimedRewardsBefore);
        console.log("Claimed Reward User1: %s", claimedRewardUser1);
        console.log("Expected Reward User1: %s", expectedRewardUser1);
        if (claimedRewardUser2 != 0 || expectedRewardUser2 != 0) {
            console.log("Claimed Reward User2: %s", claimedRewardUser2);
            console.log("Expected Reward User2: %s", expectedRewardUser2);
        }
        console.log("Unclaimed Rewards After: %s", unclaimedRewardsAfter);
        console.log("Reward Coefficient Before: %s", rewardCoefficientBefore);
        console.log("Reward Coefficient After: %s", rewardCoefficientAfter);
        console.log(
            "Total Reward Allocated Before: %s",
            totalRewardAllocatedBefore
        );
        console.log(
            "Total Reward Allocated After: %s",
            totalRewardAllocatedAfter
        );
        console.log("Remaining Rewards: %s", remainingRewards);
    }
}
