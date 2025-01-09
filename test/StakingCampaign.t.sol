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
        stakeToken.transfer(user1, 1000);
        stakeToken.transfer(user2, 1000);

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
        vm.startPrank(user1);
        stakeToken.approve(address(campaignContract), 500);
        campaignContract.stakeTokens(0, address(stakeToken), 500);
        vm.stopPrank();

        vm.startPrank(user2);
        stakeToken.approve(address(campaignContract), 500);
        campaignContract.stakeTokens(0, address(stakeToken), 500);
        vm.stopPrank();
    }

    function testSettleRewards() public {
        testStakeTokens();
        vm.warp(block.timestamp + 1 hours);
        vm.startPrank(owner);
        campaignContract.settleRewards(0);
        vm.stopPrank();
        // helper.printCampaignMetadata(0);
    }

    function testClaimRewards() public {
        testSettleRewards();
        vm.warp(block.timestamp + 10 seconds);

        vm.startPrank(user1);
        uint256 initialRewardBalance1 = rewardToken.balanceOf(user1);
        uint256 initialStakeBalance1 = stakeToken.balanceOf(user1);
        campaignContract.claimRewards(0);
        uint256 finalRewardBalance1 = rewardToken.balanceOf(user1);
        uint256 finalStakeBalance1 = stakeToken.balanceOf(user1);
        assert(finalRewardBalance1 > initialRewardBalance1);
        assert(finalStakeBalance1 == initialStakeBalance1 + 500);
        vm.stopPrank();

        vm.startPrank(user2);
        uint256 initialRewardBalance2 = rewardToken.balanceOf(user2);
        uint256 initialStakeBalance2 = stakeToken.balanceOf(user2);
        campaignContract.claimRewards(0);
        uint256 finalRewardBalance2 = rewardToken.balanceOf(user2);
        uint256 finalStakeBalance2 = stakeToken.balanceOf(user2);
        assert(finalRewardBalance2 > initialRewardBalance2);
        assert(finalStakeBalance2 == initialStakeBalance2 + 500);
        vm.stopPrank();
        helper.printCampaignMetadata(0);
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
