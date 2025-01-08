// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../test/mocks/MockERC20.sol";
import "../src/StakingCampaign.sol";

contract CounterTest is Test {
    StakingCampaign stakingCampaign;
    MockERC20 token;
    Helper public helper;
    address public alice;

    function setUp() public {
        console.log("!!!!!!!!!!!!!!!setUp!!!!!");
        stakingCampaign = new StakingCampaign(address(this));

        token = new MockERC20(1000, "Test Token", 18, "TT");
        helper = new Helper();

        alice = address(1);
    }

    function testStake() public {
        uint256 amount = 100;
        emit log("!!!!!!!!!!!!!!!stake success emitted!!!!!");
        console.log("!before!", block.timestamp);
        vm.warp(300);
        console.log("!after!", block.timestamp);
        assertEq(amount, 100);
    }
}

contract Helper {
    function whoCalled() public view returns (address) {
        return msg.sender;
    }
}
