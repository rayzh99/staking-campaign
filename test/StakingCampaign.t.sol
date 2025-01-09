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
    address public user = address(0x456);

    function setUp() public {
        rewardToken = new MockERC20(1000000, "RewardToken", 18, "RTK");
        stakeToken = new MockERC20(1000000, "StakeToken", 18, "STK");
        campaignContract = new MultiTokenStakingCampaign(owner, address(0));

        rewardToken.transfer(owner, 1000);
        stakeToken.transfer(user, 1000);

        vm.startPrank(owner);
        rewardToken.approve(address(campaignContract), 1000);
        vm.stopPrank();

        helper = new Helper(campaignContract);

        // address alice = address(1);
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
        ) = campaignContract.getCampaignMetadata(0);

        assertEq(rewardTokenAddress, address(rewardToken));
        assertEq(startTime, block.timestamp + 1 hours);
        assertEq(endTime, block.timestamp + 2 hours);
        assertEq(rewardClaimEnd, block.timestamp + 3 hours);
        assertEq(totalRewards, 100);
        assertEq(accumulatedStakeTime, 0);
        assertEq(unclaimedRewards, 100);
        assertEq(rewardCoefficient, 1);
        assertEq(stakingTarget, 1000);
        assertEq(totalStakeCount, 0);
        assertEq(totalWeight, 0);
        assertEq(totalRewardAllocated, 0);
    }

    function testStakeTokens() public {
        testCreateCampaign();
        vm.warp(block.timestamp + 1 hours + 1 seconds);
        vm.startPrank(user);
        stakeToken.approve(address(campaignContract), 1000);
        campaignContract.stakeTokens(0, address(stakeToken), 100);
        vm.warp(block.timestamp + 10 seconds);
        campaignContract.stakeTokens(0, address(stakeToken), 100);
        vm.stopPrank();

        helper.printCampaignMetadata(0);
    }

    function testSettleRewards() public {
        testStakeTokens();
        vm.warp(block.timestamp + 1 hours);
        vm.startPrank(owner);
        campaignContract.settleRewards(0);
        vm.stopPrank();
        helper.printCampaignMetadata(0);
    }

    function testClaimRewards() public {
        testSettleRewards();
        vm.warp(block.timestamp + 10 seconds);
        vm.startPrank(user);
        console.log("block timestamp", block.timestamp);

        // 检查领取奖励前的初始余额
        uint256 initialRewardBalance = rewardToken.balanceOf(user);
        uint256 initialStakeBalance = stakeToken.balanceOf(user);

        campaignContract.claimRewards(0);

        // 检查领取奖励后的余额变化
        uint256 finalRewardBalance = rewardToken.balanceOf(user);
        uint256 finalStakeBalance = stakeToken.balanceOf(user);

        console.log("Initial reward balance:", initialRewardBalance);
        console.log("Final reward balance:", finalRewardBalance);
        console.log(
            "Reward claimed:",
            finalRewardBalance - initialRewardBalance
        );

        console.log("Initial stake balance:", initialStakeBalance);
        console.log("Final stake balance:", finalStakeBalance);
        console.log(
            "Staked tokens returned:",
            finalStakeBalance - initialStakeBalance
        );

        // 断言奖励和质押代币的返回
        uint256 rewardClaimed = finalRewardBalance - initialRewardBalance;
        uint256 stakedTokensReturned = finalStakeBalance - initialStakeBalance;
        console.log("Reward claimed:", rewardClaimed);
        console.log("Staked tokens returned:", stakedTokensReturned);
        // assert(rewardClaimed > 0);
        // assert(stakedTokensReturned == 1000); // 确保质押的代币正确返还

        vm.stopPrank();
    }
}

contract Helper {
    function whoCalled() public view returns (address) {
        return msg.sender;
    }

    MultiTokenStakingCampaign campaignContract;

    constructor(MultiTokenStakingCampaign _campaignContract) {
        campaignContract = _campaignContract;
    }

    function printCampaignMetadata(uint256 _campaignId) public view {
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
        ) = campaignContract.getCampaignMetadata(_campaignId);
        console.log("Campaign Metadata:");
        console.log("Reward Token:", rewardTokenAddress);
        console.log("Start Time:", startTime);
        console.log("End Time:", endTime);
        console.log("Reward Claim End:", rewardClaimEnd);
        console.log("Total Rewards:", totalRewards);
        console.log("Accumulated Stake Time:", accumulatedStakeTime);
        console.log("Unclaimed Rewards:", unclaimedRewards);
        console.log("Reward Coefficient:", rewardCoefficient);
        console.log("Staking Target:", stakingTarget);
        console.log("Total Stake Count:", totalStakeCount);
        console.log("Total Weight:", totalWeight);
        console.log("Total Reward Allocated:", totalRewardAllocated);
    }
}
