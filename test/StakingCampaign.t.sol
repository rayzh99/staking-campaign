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
        console.log("!!!!!!!!!!!!!!!setUp!!!!!");
        rewardToken = new MockERC20(1000000, "RewardToken", 18, "RTK");
        stakeToken = new MockERC20(1000000, "StakeToken", 18, "STK");
        campaignContract = new MultiTokenStakingCampaign(owner, address(0));

        rewardToken.transfer(owner, 1000);
        stakeToken.transfer(user, 1000);

        vm.startPrank(owner);
        rewardToken.approve(address(campaignContract), 1000);
        vm.stopPrank();

        helper = new Helper();

        address alice = address(1);
    }

    function testCreateCampaign() public {
        vm.startPrank(owner);
        campaignContract.createCampaign(
            address(rewardToken),
            block.timestamp + 1 hours,
            block.timestamp + 2 hours,
            block.timestamp + 3 hours,
            100
        );
        vm.stopPrank();
    }

    function testStakeTokens() public {
        testCreateCampaign();
        vm.warp(block.timestamp + 1 hours + 1 seconds);
        vm.startPrank(user);
        stakeToken.approve(address(campaignContract), 1000);
        campaignContract.stakeTokens(0, address(stakeToken), 1000);
        vm.stopPrank();
    }

    function testSettleRewards() public {
        testStakeTokens();
        vm.warp(block.timestamp + 1 hours + 1 seconds);
        vm.startPrank(owner);
        campaignContract.settleRewards(0);
        vm.stopPrank();
        (, , , , , uint256 accumulatedStakeTime) = campaignContract
            .getCampaignMetadata(0);
        console.log(
            "Accumulated stake time after settle:",
            accumulatedStakeTime
        );
    }

    function testClaimRewards() public {
        testSettleRewards();
        vm.warp(block.timestamp + 10 seconds);
        vm.startPrank(user);
        console.log("block timestamp", block.timestamp);
        campaignContract.claimRewards(0);
        vm.stopPrank();
    }
}

contract Helper {
    function whoCalled() public view returns (address) {
        return msg.sender;
    }
}
