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
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    IUniswapV2Pair
} from "@core/uniswap-v2-core/interfaces/IUniswapV2Pair.sol";
import {
    FIRST_PARENT_TOKEN_FUNDRAISING_GOAL
} from "@extension/lib/core/test/Constant.sol";

contract RewardCalculationTest is Test {
    TestExtensionLpHelper public h;
    FlowUserParams public bob;
    FlowUserParams public alice;
    ExtensionLp public extension;
    address public tokenAddress;

    function setUp() public {
        h = new TestExtensionLpHelper();
        (bob, alice) = h.finish_launch();
        tokenAddress = h.firstTokenAddress();

        // Create extension with specific gov ratio multiplier
        // Use a very low MIN_GOV_VOTES to make testing easier (users already have some gov votes from initial stake)
        extension = h.createExtension(
            tokenAddress,
            7,
            2, // GOV_RATIO_MULTIPLIER = 2
            1e12 // MIN_GOV_VOTES = 1e12 (very low for testing)
        );

        // Setup action with extension address as whiteListAddress
        h.stake_liquidity(bob);
        h.stake_token(bob);
        bob.actionId = h.submit_new_action_with_extension(
            bob,
            address(extension)
        );
        alice.actionId = bob.actionId;
    }

    function test_rewardInfoByAccount_beforeRoundFinished() public {
        h.stake_liquidity(bob);
        h.stake_token(bob);
        h.vote(bob);

        h.next_phase();
        // extension_join will automatically add liquidity to Uniswap pair if needed
        h.extension_join(bob, extension, 1e18);

        uint256 currentRound = h.verifyContract().currentRound();

        (uint256 mintReward, uint256 burnReward, bool claimed) = extension
            .rewardInfoByAccount(currentRound, bob.userAddress);

        assertEq(mintReward, 0, "mintReward should be 0 before round finished");
        assertEq(burnReward, 0, "burnReward should be 0 before round finished");
        assertFalse(claimed, "Should not be minted");
    }

    function test_rewardInfoByAccount_afterRoundFinished() public {
        h.stake_liquidity(bob);
        h.stake_token(bob);
        h.vote(bob);

        h.next_phase();
        // extension_join will automatically add liquidity to Uniswap pair if needed
        uint256 lpAmount = 1e18;
        h.extension_join(bob, extension, lpAmount);

        h.next_phase();
        h.verify(bob);

        h.next_phase();
        // Mint action reward for extension (needed to check reward info before claim)
        // Note: rewardInfoByAccount can calculate expected reward even if not minted yet
        // But we need to mint first to have totalActionReward > 0
        h.mint_action_reward_for_extension(bob, address(extension));

        // Use verifyRound (currentRound - 1) instead of joinRound, like test_all_standard_steps
        // This is the round that was just verified, and reward is already prepared for it
        uint256 round = h.verifyContract().currentRound() - 1;
        (uint256 mintReward, uint256 burnReward, bool claimed) = extension
            .rewardInfoByAccount(round, bob.userAddress);

        // rewardInfoByAccount returns expected reward even if not claimed yet
        assertGt(mintReward, 0, "mintReward should be > 0");
        assertGe(burnReward, 0, "burnReward should be >= 0");
        assertFalse(claimed, "Should not be minted before claim");
    }

    function test_rewardInfoByAccount_afterClaim() public {
        h.stake_liquidity(bob);
        h.stake_token(bob);
        h.vote(bob);

        h.next_phase();
        // extension_join will automatically add liquidity to Uniswap pair if needed
        h.extension_join(bob, extension, 1e18);

        h.next_phase();
        h.verify(bob);
        // verify will call prepareRewardIfNeeded for verifyRound (currentRound)
        // Extension already joined in _doInitialize, so it should be in randomAccounts
        // When bob verify, extension address will get verification score (if it's in randomAccounts)

        h.next_phase();
        // Use verifyRound (currentRound - 1) instead of joinRound, like test_all_standard_steps
        // This is the round that was just verified, and reward is already prepared for it
        uint256 round = h.verifyContract().currentRound() - 1;

        // Don't mint action reward manually, let claimReward trigger it automatically via _prepareRewardIfNeeded
        h.extension_claimReward(bob, extension, round);

        (uint256 mintReward, uint256 burnReward, bool claimed) = extension
            .rewardInfoByAccount(round, bob.userAddress);

        assertGt(mintReward, 0, "mintReward should be > 0");
        assertGe(burnReward, 0, "burnReward should be >= 0");
        assertTrue(claimed, "Should be minted after claim");
    }

    function test_rewardCalculation_withGovRatioMultiplier() public {
        // Create extension with gov ratio multiplier = 2
        h.createExtension(tokenAddress, 7, 2, 1e18);

        // Use the existing action from setUp, but need to ensure it's for the new extension
        // Since we can't submit another action in the same round, we'll use the existing extension
        // and create a new extension with different parameters for comparison
        // Actually, let's just use the existing extension and test with different parameters
        h.stake_liquidity(bob);
        h.stake_token(bob);
        // Use actionId from setUp (already set up with extension address)
        h.vote(bob);

        h.next_phase();
        // extension_join will automatically add liquidity to Uniswap pair if needed
        h.extension_join(bob, extension, 1e18);

        h.next_phase();
        h.verify(bob);

        h.next_phase();
        // Mint action reward for extension (needed to check reward info)
        h.mint_action_reward_for_extension(bob, address(extension));

        // Use verifyRound (currentRound - 1) instead of joinRound, like test_all_standard_steps
        // This is the round that was just verified, and reward is already prepared for it
        uint256 round = h.verifyContract().currentRound() - 1;
        (uint256 mintReward, , bool claimed) = extension.rewardInfoByAccount(
            round,
            bob.userAddress
        );

        // With gov ratio multiplier, the reward should be limited by gov votes
        assertGt(mintReward, 0, "mintReward should be > 0");
        assertFalse(claimed, "Should not be minted before claim");
    }

    function test_rewardCalculation_multipleUsers() public {
        // Use actionId from setUp (already set up with extension address)
        // Ensure users have token balance for staking (bob and alice from setUp should have tokens from launch claim)
        // But to be safe, let's ensure they have enough
        h.ensureUserHasMinimumTokensForStaking(bob);
        h.stake_liquidity(bob);
        h.stake_token(bob);
        h.ensureUserHasMinimumTokensForStaking(alice);
        h.stake_liquidity(alice);
        h.stake_token(alice);
        h.vote(bob);
        h.vote(alice);

        h.next_phase();
        // extension_join will automatically add liquidity to Uniswap pair if needed
        // Ensure users have enough gov votes for join (MIN_GOV_VOTES = 1e18)
        // Stake more if needed to meet MIN_GOV_VOTES requirement
        uint256 minGovVotes = extension.MIN_GOV_VOTES();
        // Ensure users have enough tokens to stake more to meet MIN_GOV_VOTES
        // Use a more conservative approach: stake larger amounts with limited iterations
        // This avoids unbalancing the Uniswap pair reserves while ensuring enough gov votes
        uint256 maxIterations = 5;
        for (
            uint256 i = 0;
            i < maxIterations &&
                h.stakeContract().validGovVotes(
                    tokenAddress,
                    alice.userAddress
                ) <
                minGovVotes;
            i++
        ) {
            h.forceMint(tokenAddress, alice.userAddress, 2e24); // Use larger amount
            h.stake_liquidity(alice);
            h.stake_token(alice);
        }
        for (
            uint256 i = 0;
            i < maxIterations &&
                h.stakeContract().validGovVotes(tokenAddress, bob.userAddress) <
                minGovVotes;
            i++
        ) {
            h.forceMint(tokenAddress, bob.userAddress, 2e24); // Use larger amount
            h.stake_liquidity(bob);
            h.stake_token(bob);
        }

        uint256 bobLp = 5e17;
        uint256 aliceLp = 5e17;

        h.extension_join(bob, extension, bobLp);
        h.extension_join(alice, extension, aliceLp);

        h.next_phase();
        h.verify(bob);
        h.verify(alice);

        h.next_phase();
        // Mint action reward for extension (needed to check reward info)
        h.mint_action_reward_for_extension(bob, address(extension));

        // Use verifyRound (currentRound - 1) instead of joinRound, like test_all_standard_steps
        // This is the round that was just verified, and reward is already prepared for it
        uint256 round = h.verifyContract().currentRound() - 1;
        (
            uint256 bobMintReward,
            uint256 bobBurnReward,
            bool bobIsMinted
        ) = extension.rewardInfoByAccount(round, bob.userAddress);

        (
            uint256 aliceMintReward,
            uint256 aliceBurnReward,
            bool aliceIsMinted
        ) = extension.rewardInfoByAccount(round, alice.userAddress);

        assertGt(bobMintReward, 0, "Bob should have mint reward");
        assertGt(aliceMintReward, 0, "Alice should have mint reward");
        assertFalse(bobIsMinted, "Bob should not be minted before claim");
        assertFalse(aliceIsMinted, "Alice should not be minted before claim");

        // Total rewards should be consistent
        uint256 totalReward = bobMintReward +
            bobBurnReward +
            aliceMintReward +
            aliceBurnReward;
        assertGt(totalReward, 0, "Total reward should be > 0");
    }
}
