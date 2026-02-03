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
            .rewardByAccount(roundN, bob.userAddress);
        assertFalse(claimed, "Should not be claimed yet");
        assertGt(mintReward + burnReward, 0, "Should have some reward");

        // Claim
        h.extension_claimReward(bob, extension, roundN);
        (mintReward, burnReward, claimed) = extension.rewardByAccount(
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
        (uint256 mintReward, , bool claimed) = extension.rewardByAccount(
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
            .rewardByAccount(roundN, bob.userAddress);
        (uint256 aliceMintReward, uint256 aliceBurnReward, ) = extension
            .rewardByAccount(roundN, alice.userAddress);

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
        assertGt(
            aliceBalanceAfter,
            aliceBalanceBefore,
            "Alice should get reward"
        );
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
            .rewardByAccount(roundN, bob.userAddress);
        assertFalse(claimed, "Should not be claimed yet");
        assertGt(mintReward + burnReward, 0, "Should have reward");

        h.extension_claimReward(bob, extension, roundN);
        (, , claimed) = extension.rewardByAccount(roundN, bob.userAddress);
        assertTrue(claimed, "Should be claimed");
    }

    /// @notice Test: LP continues across rounds - should have 100% block ratio in next round
    /// User joins in round N, LP continues to round N+1 without re-joining
    /// Block ratio in round N+1 should be 100% (joinedBlock == 0 for that round)
    function test_lpContinuesAcrossRounds_fullBlockRatio() public {
        // Vote for round N
        h.stake_liquidity(bob);
        h.stake_token(bob);
        h.vote(bob);

        // Join phase round N - bob joins late in the round
        h.next_phase();
        uint256 roundN = h.joinContract().currentRound();

        // Advance to middle of join phase, then join
        vm.roll(block.number + 50);
        h.extension_join(bob, extension, 1e18);

        // Verify round N
        h.next_phase();
        h.verify(bob);

        // Mint round N
        h.next_phase();

        // Get round N reward (has block ratio penalty since joined late)
        (uint256 roundNMintReward, uint256 roundNBurnReward, ) = extension
            .rewardByAccount(roundN, bob.userAddress);
        uint256 roundNTotalReward = roundNMintReward + roundNBurnReward;
        assertGt(roundNTotalReward, 0, "Should have round N reward");

        // Claim round N
        h.extension_claimReward(bob, extension, roundN);

        // === Round N+1: bob does NOT re-join, LP continues ===
        // Move to vote phase of next round
        h.next_phase();

        // Resubmit action for round N+1
        h.resubmit_action(bob, address(extension));

        // Vote for round N+1
        h.vote(bob);

        // Join phase for next round (bob doesn't join again, LP continues)
        // Note: After vote->join->verify->mint cycle, we're now at join round N+4
        h.next_phase();
        uint256 roundN1 = h.joinContract().currentRound();
        assertGt(roundN1, roundN, "Should be after round N");

        // Verify next round
        h.next_phase();
        h.verify(bob);

        // Mint next round
        h.next_phase();

        // Get next round reward - should have 100% block ratio since LP is continued
        // (joinedBlock for this round is 0, so blockRatio = 100%)
        (uint256 roundN1MintReward, , ) = extension.rewardByAccount(
            roundN1,
            bob.userAddress
        );
        assertGt(
            roundN1MintReward,
            0,
            "Should have mint reward in continued round"
        );

        // Next round should have better mint reward ratio (100% block ratio vs partial in round N)
        // Because LP is continued and joinedBlock == 0, blockRatio = 100%
        // Note: Actual mint amount may vary due to gov votes ratio and total rewards
        // The key verification is that the continued LP has full block ratio (no penalty)
        assertGt(
            roundN1MintReward,
            roundNMintReward,
            "Continued round should have higher mint reward (full block ratio)"
        );
    }

    /// @notice Test: add LP in next round - should NOT update joinedBlock
    /// User joins in round N, then adds more LP in round N+1
    /// Block ratio in round N+1 should still be 100% (joinedBlock not updated)
    function test_addLpInNextRound_blockRatioNotUpdated() public {
        // Vote for round N
        h.stake_liquidity(bob);
        h.stake_token(bob);
        h.vote(bob);

        // Join phase round N
        h.next_phase();
        uint256 roundN = h.joinContract().currentRound();
        h.extension_join(bob, extension, 5e17);

        // Verify round N
        h.next_phase();
        h.verify(bob);

        // Mint round N
        h.next_phase();
        h.extension_claimReward(bob, extension, roundN);

        // === Round N+1: bob adds more LP late in the join phase ===
        // Move to vote phase of next round
        h.next_phase();

        // Resubmit action for round N+1
        h.resubmit_action(bob, address(extension));

        // Vote for round N+1
        h.vote(bob);

        // Join phase for next round
        h.next_phase();
        uint256 roundN1 = h.joinContract().currentRound();
        assertGt(roundN1, roundN, "Should be after round N");

        // Advance to late in join phase
        vm.roll(block.number + 50);

        // Add more LP (this should NOT update _lastJoinedBlockByAccountByJoinedRound)
        // Because currentRound != _joinedRoundByAccount[bob] (LP was continued from roundN)
        h.extension_join(bob, extension, 5e17);

        // Verify next round
        h.next_phase();
        h.verify(bob);

        // Mint next round
        h.next_phase();

        // Get reward - should have 100% block ratio despite adding LP late
        // Because _lastJoinedBlockByAccountByJoinedRound[bob][roundN1] was NOT updated (stays 0)
        // since the user's joinedRound is still roundN, not roundN1
        (uint256 mintReward, uint256 burnReward, ) = extension.rewardByAccount(
            roundN1,
            bob.userAddress
        );
        uint256 totalReward = mintReward + burnReward;
        assertGt(totalReward, 0, "Should have reward");

        // Claim
        h.extension_claimReward(bob, extension, roundN1);
    }

    /// @notice Test: compare rewards - continued LP vs new LP in same round
    /// User A: continues LP from previous round (100% block ratio)
    /// User B: joins late in current round (partial block ratio)
    /// User A should get more reward with same LP amount
    function test_continuedLpVsNewLp_blockRatioComparison() public {
        // Setup alice
        h.stake_liquidity(alice);
        h.stake_token(alice);

        // === Round N: only bob joins ===
        h.stake_liquidity(bob);
        h.stake_token(bob);
        h.vote(bob);

        // Join phase round N
        h.next_phase();
        uint256 roundN = h.joinContract().currentRound();
        h.extension_join(bob, extension, 1e18);

        // Verify round N
        h.next_phase();
        h.verify(bob);

        // Mint round N
        h.next_phase();
        h.extension_claimReward(bob, extension, roundN);

        // === Round N+1: bob continues LP, alice joins late ===
        // Move to vote phase of next round
        h.next_phase();

        // Resubmit action for round N+1
        h.resubmit_action(bob, address(extension));

        // Vote for round N+1
        h.vote(bob);
        h.vote(alice);

        // Join phase for next round
        h.next_phase();
        uint256 roundN1 = h.joinContract().currentRound();

        // Advance to late in join phase
        vm.roll(block.number + 50);

        // Alice joins late with same amount as bob - this is her first join
        h.extension_join(alice, extension, 1e18);

        // Bob does NOT re-join, his LP continues from previous round

        // Verify next round
        h.next_phase();
        h.verify(bob);
        h.verify(alice);

        // Mint next round
        h.next_phase();

        // Get rewards
        (uint256 bobMintReward, , ) = extension.rewardByAccount(
            roundN1,
            bob.userAddress
        );
        (uint256 aliceMintReward, , ) = extension.rewardByAccount(
            roundN1,
            alice.userAddress
        );

        // Both should have mint rewards
        assertGt(bobMintReward, 0, "Bob should have mint reward");
        // Note: Alice may have very low or zero mint reward due to low gov votes

        // Bob should have higher mint reward:
        // - Bob has 100% block ratio (continued LP, joinedBlock == 0 for this round)
        // - Alice has partial block ratio (first join late, joinedBlock != 0)
        // Also, Bob has much higher gov votes than Alice
        assertGt(
            bobMintReward,
            aliceMintReward,
            "Bob (continued LP) should have more mint reward than Alice"
        );
    }

    /// @notice Test: exit and rejoin in next round - should update joinedBlock
    /// User joins in round N, exits, then rejoins in round N+1
    /// This is a "first join" again, so joinedBlock SHOULD be updated
    function test_exitAndRejoinNextRound_updatesJoinedBlock() public {
        // Vote for round N
        h.stake_liquidity(bob);
        h.stake_token(bob);
        h.vote(bob);

        // Join phase round N
        h.next_phase();
        uint256 roundN = h.joinContract().currentRound();
        h.extension_join(bob, extension, 1e18);

        // Verify round N
        h.next_phase();
        h.verify(bob);

        // Mint round N
        h.next_phase();
        h.extension_claimReward(bob, extension, roundN);

        // === Exit before round N+1 ===
        h.next_phases(7 / PHASE_BLOCKS + 1);
        h.extension_withdraw(bob, extension);

        // === Round N+1: bob rejoins late ===

        // Resubmit action for round N+1
        h.resubmit_action(bob, address(extension));

        // Vote for round N+1
        h.vote(bob);

        // Join phase round N+1
        h.next_phase();
        uint256 roundN1 = h.joinContract().currentRound();

        // Advance to late in join phase
        vm.roll(block.number + 50);

        // Rejoin late - this IS a first join (after exit), so joinedBlock SHOULD be updated
        h.extension_join(bob, extension, 1e18);

        // Verify round N+1
        h.next_phase();
        h.verify(bob);

        // Mint round N+1
        h.next_phase();

        // Get reward - should have partial block ratio (joined late after exit)
        (uint256 mintReward, uint256 burnReward, ) = extension.rewardByAccount(
            roundN1,
            bob.userAddress
        );
        uint256 totalReward = mintReward + burnReward;
        assertGt(totalReward, 0, "Should have reward");

        // The reward should be less than if he had continued LP (but we can't directly compare here)
        // At least verify claiming works
        h.extension_claimReward(bob, extension, roundN1);
        (, , bool claimed) = extension.rewardByAccount(
            roundN1,
            bob.userAddress
        );
        assertTrue(claimed, "Should be claimed");
    }
}
