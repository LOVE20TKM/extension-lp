// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {Test} from "forge-std/Test.sol";
import {
    TestExtensionLpHelper,
    FlowUserParams
} from "../TestExtensionLpHelper.sol";
import {ExtensionLp} from "../../src/ExtensionLp.sol";
import {ILp} from "../../src/interface/ILp.sol";
import {ILOVE20Token} from "@core/interfaces/ILOVE20Token.sol";
import {ILOVE20Mint} from "@core/interfaces/ILOVE20Mint.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    IUniswapV2Pair
} from "@core/uniswap-v2-core/interfaces/IUniswapV2Pair.sol";
import {
    FIRST_PARENT_TOKEN_FUNDRAISING_GOAL,
    PHASE_BLOCKS
} from "@extension/lib/core/test/Constant.sol";

contract FlowTest is Test {
    TestExtensionLpHelper public h;
    FlowUserParams public bob;
    FlowUserParams public alice;
    ExtensionLp public extension;
    address public tokenAddress;

    function setUp() public {
        h = new TestExtensionLpHelper();

        // Finish launch to get token
        (bob, alice) = h.finish_launch();
        tokenAddress = h.firstTokenAddress();

        // Create extension
        extension = h.createExtensionWithDefaults(tokenAddress);

        // Stake tokens first (required for submit)
        h.stake_liquidity(bob);
        h.stake_token(bob);

        // Setup action with extension address as whiteListAddress
        bob.actionId = h.submit_new_action_with_extension(
            bob,
            address(extension)
        );
        alice.actionId = bob.actionId;
    }

    function test_all_standard_steps() public {
        // Stake & submit & vote
        h.stake_liquidity(bob);
        h.stake_token(bob);
        h.vote(bob);

        // Join with LP tokens
        h.next_phase();
        // extension_join will automatically add liquidity to Uniswap pair if needed
        // Use a reasonable amount (e.g., 1e18 LP tokens)
        h.extension_join(bob, extension, 1e18);
        // Join again with more LP tokens
        h.extension_join(bob, extension, 5e17);

        // Verify
        h.next_phase();
        h.verify(bob);

        // Mint gov reward (action reward will be minted automatically via claimReward)
        h.next_phase();
        h.mint_gov_reward(bob);

        // Claim extension reward (this will automatically trigger mintActionReward via _prepareRewardIfNeeded)
        uint256 round = h.verifyContract().currentRound() - 1;
        h.extension_claimReward(bob, extension, round);

        // Withdraw from extension
        h.next_phases(7 / PHASE_BLOCKS + 1);
        h.extension_withdraw(bob, extension);

        // Exit from core (for ExtensionLp, users don't join directly in core, so no need to withdraw)
        h.stake_unstake(bob);
        h.next_phases(bob.stake.promisedWaitingPhases + 1);
        h.stake_withdraw(bob);

        // Note: For ExtensionLp, users join through extension, not directly in core
        // So we don't need to call join_withdraw from core
        h.burnForParentToken(bob);
    }

    function test_join_with_lp_tokens() public {
        // Use actionId from setUp
        h.vote(bob);

        h.next_phase();

        // extension_join will automatically add liquidity to Uniswap pair if needed
        // Use a fixed amount (e.g., 1e18 LP tokens)
        h.extension_join(bob, extension, 1e18);

        // Note: extension_join may use all LP tokens, so balance might be less than 1e18
        // Just check that join was successful

        (
            uint256 joinedRound,
            uint256 amount,
            ,
            uint256 exitableBlock
        ) = extension.joinInfo(bob.userAddress);
        assertEq(joinedRound, h.joinContract().currentRound());
        assertGe(amount, 1e18, "Amount should be at least 1e18");
        assertGt(exitableBlock, block.number);
    }

    function test_claim_reward_after_mint() public {
        // Use actionId from setUp
        h.vote(bob);

        h.next_phase();
        // extension_join will automatically add liquidity to Uniswap pair if needed
        // Use a fixed amount (e.g., 1e18 LP tokens)
        h.extension_join(bob, extension, 1e18);

        h.next_phase();
        h.verify(bob);

        h.next_phase();
        // Don't call mint_action_reward directly, let claimReward trigger it automatically
        uint256 round = h.verifyContract().currentRound() - 1;
        uint256 balanceBefore = IERC20(tokenAddress).balanceOf(bob.userAddress);

        h.extension_claimReward(bob, extension, round);

        uint256 balanceAfter = IERC20(tokenAddress).balanceOf(bob.userAddress);
        assertGt(balanceAfter, balanceBefore, "Should receive reward");
    }

    function test_claimRewards_batchClaim() public {
        // Round N
        h.stake_liquidity(bob);
        h.stake_token(bob);
        h.vote(bob);

        h.next_phase();
        h.extension_join(bob, extension, 1e18);

        h.next_phase();
        h.verify(bob);

        h.next_phase(); // mint phase
        uint256 round1 = h.verifyContract().currentRound() - 1;

        // Round N+1
        h.next_phase(); // next vote phase
        h.resubmit_action(bob, address(extension));
        h.vote(bob);

        h.next_phase(); // join phase (bob doesn't join again, LP continues)

        h.next_phase(); // verify
        h.verify(bob);

        h.next_phase(); // mint
        uint256 round2 = h.verifyContract().currentRound() - 1;

        assertGt(round2, round1, "Round 2 should be after round 1");

        // Batch claim both rounds
        uint256[] memory rounds = new uint256[](2);
        rounds[0] = round1;
        rounds[1] = round2;

        uint256 balanceBefore = IERC20(tokenAddress).balanceOf(bob.userAddress);

        vm.prank(bob.userAddress);
        (
            uint256[] memory claimedRounds,
            uint256[] memory mintRewards,

        ) = extension.claimRewards(rounds);

        uint256 balanceAfter = IERC20(tokenAddress).balanceOf(bob.userAddress);

        assertEq(claimedRounds.length, 2, "Should claim 2 rounds");
        assertGt(mintRewards[0], 0, "Round 1 mint > 0");
        assertGt(mintRewards[1], 0, "Round 2 mint > 0");
        assertEq(
            balanceAfter - balanceBefore,
            mintRewards[0] + mintRewards[1],
            "Balance change should equal total mint"
        );

        // Verify both marked as claimed
        (, , bool c1) = extension.rewardByAccount(round1, bob.userAddress);
        (, , bool c2) = extension.rewardByAccount(round2, bob.userAddress);
        assertTrue(c1, "Round 1 claimed");
        assertTrue(c2, "Round 2 claimed");
    }
}
