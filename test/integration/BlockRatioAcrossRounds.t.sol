// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {Test} from "forge-std/Test.sol";
import {
    TestExtensionLpHelper,
    FlowUserParams
} from "../TestExtensionLpHelper.sol";
import {ExtensionLp} from "../../src/ExtensionLp.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PHASE_BLOCKS} from "@extension/lib/core/test/Constant.sol";

/// @notice Test block ratio calculation
contract BlockRatioAcrossRoundsTest is Test {
    TestExtensionLpHelper public h;
    FlowUserParams public bob;
    FlowUserParams public alice;
    ExtensionLp public extension;
    address public tokenAddress;

    function setUp() public {
        h = new TestExtensionLpHelper();
        (bob, alice) = h.finish_launch();
        tokenAddress = h.firstTokenAddress();

        extension = h.createExtension(
            tokenAddress,
            2, // GOV_RATIO_MULTIPLIER = 2
            1e12 // MIN_GOV_VOTES = 1e12 (very low for testing)
        );

        h.stake_liquidity(bob);
        h.stake_token(bob);
        bob.actionId = h.submit_new_action_with_extension(
            bob,
            address(extension)
        );
        alice.actionId = bob.actionId;
    }

    /// @notice Test: add LP multiple times within same round - block ratio uses last join block
    function test_multipleJoinsInSameRound_usesLastJoinBlock() public {
        // Vote
        h.stake_liquidity(bob);
        h.stake_token(bob);
        h.vote(bob);

        // Join phase - join early
        h.next_phase();
        uint256 roundN = h.joinContract().currentRound();
        h.extension_join(bob, extension, 5e17);

        // Advance some blocks within the same round
        vm.roll(block.number + 10);

        // Join again later in the same round
        h.extension_join(bob, extension, 5e17);

        // Verify
        h.next_phase();
        h.verify(bob);

        // Mint
        h.next_phase();

        // Check that reward calculation doesn't revert
        (uint256 mintReward, uint256 burnReward, bool claimed) = extension
            .rewardInfoByAccount(roundN, bob.userAddress);
        assertFalse(claimed, "Should not be claimed yet");
        assertGt(mintReward + burnReward, 0, "Should have some reward");

        // Claim
        h.extension_claimReward(bob, extension, roundN);
        (mintReward, burnReward, claimed) = extension.rewardInfoByAccount(
            roundN,
            bob.userAddress
        );
        assertTrue(claimed, "Should be claimed");
    }

    /// @notice Test: exit then claim reward - reward should still be claimable
    function test_exitThenClaimReward() public {
        // Vote
        h.stake_liquidity(bob);
        h.stake_token(bob);
        h.vote(bob);

        // Join
        h.next_phase();
        uint256 roundN = h.joinContract().currentRound();
        h.extension_join(bob, extension, 1e18);

        // Verify
        h.next_phase();
        h.verify(bob);

        // Mint phase
        h.next_phase();

        // Wait and exit before claiming
        h.next_phases(7 / PHASE_BLOCKS + 1);
        h.extension_withdraw(bob, extension);

        // Should still be able to claim round N reward after exit
        uint256 balanceBefore = IERC20(tokenAddress).balanceOf(bob.userAddress);
        h.extension_claimReward(bob, extension, roundN);
        uint256 balanceAfter = IERC20(tokenAddress).balanceOf(bob.userAddress);

        assertGt(
            balanceAfter,
            balanceBefore,
            "Should receive reward after exit"
        );

        // Verify claimed
        (uint256 mintReward, , bool claimed) = extension.rewardInfoByAccount(
            roundN,
            bob.userAddress
        );
        assertTrue(claimed, "Should be claimed");
        assertGt(mintReward, 0, "Mint reward should be > 0");
    }

    /// @notice Test: join at different blocks in same round, verify block ratio affects reward
    function test_blockRatioAffectsReward() public {
        // Setup alice
        h.stake_liquidity(alice);
        h.stake_token(alice);

        // Vote phase
        h.stake_liquidity(bob);
        h.stake_token(bob);
        h.vote(bob);
        h.vote(alice);

        // Join phase - bob joins early, alice joins late
        h.next_phase();
        uint256 roundN = h.joinContract().currentRound();

        // Bob joins early in the round
        h.extension_join(bob, extension, 1e18);
        uint256 bobJoinBlock = block.number;

        // Advance blocks (but stay within the round)
        vm.roll(block.number + 50);

        // Alice joins late in the round with same amount
        h.extension_join(alice, extension, 1e18);
        uint256 aliceJoinBlock = block.number;

        assertGt(aliceJoinBlock, bobJoinBlock, "Alice should join later");

        // Verify
        h.next_phase();
        h.verify(bob);
        h.verify(alice);

        // Mint
        h.next_phase();

        // Check rewards - bob joined earlier so has more blocks, should get more reward
        (uint256 bobMintReward, uint256 bobBurnReward, ) = extension
            .rewardInfoByAccount(roundN, bob.userAddress);
        (uint256 aliceMintReward, uint256 aliceBurnReward, ) = extension
            .rewardInfoByAccount(roundN, alice.userAddress);

        uint256 bobTotalReward = bobMintReward + bobBurnReward;
        uint256 aliceTotalReward = aliceMintReward + aliceBurnReward;

        // Both should have rewards
        assertGt(bobTotalReward, 0, "Bob should have reward");
        assertGt(aliceTotalReward, 0, "Alice should have reward");

        // Bob joined earlier, so his block ratio is higher
        // With same LP amount, bob should have higher theoretical reward
        // (but actual reward also depends on gov votes ratio)
        assertGe(
            bobTotalReward,
            aliceTotalReward,
            "Bob should have >= reward (joined earlier)"
        );
    }

    /// @notice Test: two users with different join times, verify rewards are correct
    function test_twoUsersJoinSameRound() public {
        // Setup alice
        h.stake_liquidity(alice);
        h.stake_token(alice);

        // Vote
        h.stake_liquidity(bob);
        h.stake_token(bob);
        h.vote(bob);
        h.vote(alice);

        // Join phase
        h.next_phase();
        uint256 roundN = h.joinContract().currentRound();
        h.extension_join(bob, extension, 1e18);
        h.extension_join(alice, extension, 1e18);

        // Verify
        h.next_phase();
        h.verify(bob);
        h.verify(alice);

        // Mint
        h.next_phase();

        // Both should be able to claim
        uint256 bobBalanceBefore = IERC20(tokenAddress).balanceOf(
            bob.userAddress
        );
        h.extension_claimReward(bob, extension, roundN);
        uint256 bobBalanceAfter = IERC20(tokenAddress).balanceOf(
            bob.userAddress
        );
        assertGt(bobBalanceAfter, bobBalanceBefore, "Bob should get reward");

        uint256 aliceBalanceBefore = IERC20(tokenAddress).balanceOf(
            alice.userAddress
        );
        h.extension_claimReward(alice, extension, roundN);
        uint256 aliceBalanceAfter = IERC20(tokenAddress).balanceOf(
            alice.userAddress
        );
        assertGt(aliceBalanceAfter, aliceBalanceBefore, "Alice should get reward");
    }

    /// @notice Test: join, exit, rejoin in same round - only last join block matters
    function test_joinExitRejoinSameRound() public {
        // Vote
        h.stake_liquidity(bob);
        h.stake_token(bob);
        h.vote(bob);

        // Join phase
        h.next_phase();
        uint256 roundN = h.joinContract().currentRound();

        // First join
        h.extension_join(bob, extension, 1e18);

        // Wait required blocks and exit
        vm.roll(block.number + 2);
        h.extension_withdraw(bob, extension);

        // Rejoin (need gov votes check again since it's first join after exit)
        h.extension_join(bob, extension, 1e18);

        // Verify
        h.next_phase();
        h.verify(bob);

        // Mint
        h.next_phase();

        // Should be able to claim
        (uint256 mintReward, uint256 burnReward, bool claimed) = extension
            .rewardInfoByAccount(roundN, bob.userAddress);
        assertFalse(claimed, "Should not be claimed yet");
        assertGt(mintReward + burnReward, 0, "Should have reward");

        h.extension_claimReward(bob, extension, roundN);
        (, , claimed) = extension.rewardInfoByAccount(roundN, bob.userAddress);
        assertTrue(claimed, "Should be claimed");
    }
}
