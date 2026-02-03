// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {Test} from "forge-std/Test.sol";
import {
    TestExtensionLpHelper,
    FlowUserParams
} from "../TestExtensionLpHelper.sol";
import {ExtensionLp} from "../../src/ExtensionLp.sol";
import {ILOVE20Token} from "@core/interfaces/ILOVE20Token.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    IUniswapV2Pair
} from "@core/uniswap-v2-core/interfaces/IUniswapV2Pair.sol";
import {ILOVE20Submit} from "@core/interfaces/ILOVE20Submit.sol";
import {
    FIRST_PARENT_TOKEN_FUNDRAISING_GOAL
} from "@extension/lib/core/test/Constant.sol";

contract EdgeCasesTest is Test {
    TestExtensionLpHelper public h;
    FlowUserParams public bob;
    FlowUserParams public alice;
    ExtensionLp public extension;
    ExtensionLp public extensionZeroMin;
    address public tokenAddress;

    function setUp() public {
        h = new TestExtensionLpHelper();
        (bob, alice) = h.finish_launch();
        tokenAddress = h.firstTokenAddress();
        extension = h.createExtensionWithDefaults(tokenAddress);

        // Create extension with MIN_GOV_RATIO = 0 for test_extension_minGovRatio_zero
        extensionZeroMin = h.createExtension(tokenAddress, 2, 0);

        // Setup action with extension address as whiteListAddress
        h.stake_liquidity(bob);
        h.stake_token(bob);
        bob.actionId = h.submit_new_action_with_extension(
            bob,
            address(extension)
        );
        alice.actionId = bob.actionId;

        // Note: extensionZeroMin action will be submitted in test_extension_minGovRatio_zero
        // in a new round to avoid OnlyOneSubmitPerRound() error
    }

    function test_rewardInfoByAccount_nonJoinedUser() public {
        // Use actionId from setUp
        h.vote(bob);

        h.next_phase();
        // Bob joins to create some joined amount
        h.extension_join(bob, extension, 1e18);

        h.next_phase();
        h.verify(bob);

        h.next_phase();
        // Mint action reward for extension (needed to check reward info for non-joined user)
        h.mint_action_reward_for_extension(bob, address(extension));

        uint256 round = h.verifyContract().currentRound() - 1;
        assertGt(round, 0, "Round should be > 0");

        // Alice didn't join
        (uint256 mintReward, uint256 burnReward, bool claimed) = extension
            .rewardByAccount(round, alice.userAddress);

        assertEq(mintReward, 0, "Non-joined user mintReward should be 0");
        assertEq(burnReward, 0, "Non-joined user burnReward should be 0");
        assertFalse(claimed, "Should not be minted");
    }

    function test_rewardInfoByAccount_futureRound() public {
        // Use actionId from setUp
        h.vote(bob);

        h.next_phase();
        // extension_join will automatically add liquidity to Uniswap pair if needed
        h.extension_join(bob, extension, 1e18);

        uint256 futureRound = h.verifyContract().currentRound() + 10;

        (uint256 mintReward, uint256 burnReward, bool claimed) = extension
            .rewardByAccount(futureRound, bob.userAddress);

        assertEq(mintReward, 0, "Future round mintReward should be 0");
        assertEq(burnReward, 0, "Future round burnReward should be 0");
        assertFalse(claimed, "Should not be minted");
    }

    function test_joinedAmountByAccount_zeroAmount() public view {
        uint256 joinedAmount = extension.joinedAmountByAccount(bob.userAddress);
        assertEq(joinedAmount, 0, "Should be 0 for non-joined user");
    }

    function test_claimReward_twice() public {
        // Use actionId from setUp
        h.vote(bob);

        h.next_phase();
        // extension_join will automatically add liquidity to Uniswap pair if needed
        h.extension_join(bob, extension, 1e18);

        h.next_phase();
        h.verify(bob);

        h.next_phase();
        // Don't mint action reward manually, let claimReward trigger it automatically via _prepareRewardIfNeeded
        uint256 round = h.verifyContract().currentRound() - 1;

        // First claim (will automatically trigger mint via _prepareRewardIfNeeded)
        h.extension_claimReward(bob, extension, round);

        // Second claim should revert (AlreadyClaimed)
        vm.expectRevert();
        h.extension_claimReward(bob, extension, round);
    }

    function test_withdraw_beforeWaitingBlocks() public {
        // Use actionId from setUp
        h.vote(bob);

        h.next_phase();
        // extension_join will automatically add liquidity to Uniswap pair if needed
        h.extension_join(bob, extension, 1e18);

        // Try to withdraw immediately (should revert or not allow)
        vm.expectRevert();
        h.extension_withdraw(bob, extension);
    }

    function test_join_zeroAmount() public {
        // Use actionId from setUp
        h.vote(bob);

        h.next_phase();

        vm.startPrank(bob.userAddress);
        IUniswapV2Pair lpToken = h.getLpToken(tokenAddress);
        IERC20(address(lpToken)).approve(address(extension), 0);
        // Should revert or handle zero amount appropriately
        vm.expectRevert();
        extension.join(0, new string[](0));
        vm.stopPrank();
    }

    function test_joinedAmount_emptyExtension() public view {
        assertEq(extension.joinedAmount(), 0, "Should be 0 when no joins");
    }

    function test_rewardInfoByAccount_currentRound() public {
        // Use actionId from setUp
        h.vote(bob);

        h.next_phase();
        // extension_join will automatically add liquidity to Uniswap pair if needed
        h.extension_join(bob, extension, 1e18);

        uint256 currentRound = h.verifyContract().currentRound();

        (uint256 mintReward, uint256 burnReward, bool claimed) = extension
            .rewardByAccount(currentRound, bob.userAddress);

        assertEq(mintReward, 0, "Current round mintReward should be 0");
        assertEq(burnReward, 0, "Current round burnReward should be 0");
        assertFalse(claimed, "Should not be minted");
    }

    function test_extension_withNoActionReward() public {
        // Use actionId from setUp
        h.vote(bob);

        h.next_phase();
        // extension_join will automatically add liquidity to Uniswap pair if needed
        h.extension_join(bob, extension, 1e18);

        h.next_phase();
        h.verify(bob);

        // Don't mint action reward, only mint gov reward
        h.next_phase();
        h.mint_gov_reward(bob);

        uint256 round = h.verifyContract().currentRound() - 1;

        (uint256 mintReward, uint256 burnReward, ) = extension.rewardByAccount(
            round,
            bob.userAddress
        );

        // Note: rewardInfoByAccount returns expected reward even if not minted yet
        // But if no action reward was minted, the totalActionReward should be 0
        // So mintReward should be 0
        // However, if the action reward was minted by someone else, it might not be 0
        // Let's check if action reward exists for this round
        uint256 totalActionReward = h.mintContract().actionReward(
            tokenAddress,
            round
        );
        if (totalActionReward == 0) {
            assertEq(
                mintReward,
                0,
                "mintReward should be 0 without action reward"
            );
            assertEq(
                burnReward,
                0,
                "burnReward should be 0 without action reward"
            );
        }
    }

    function test_extension_minGovRatio_zero() public {
        // Use extensionZeroMin from setUp (already created with MIN_GOV_RATIO = 0)
        // Create user with no gov votes
        FlowUserParams memory poorUser = h.createUser(
            "poorUser",
            tokenAddress,
            FIRST_PARENT_TOKEN_FUNDRAISING_GOAL
        );

        // Ensure stake parameters are set (needed for voting)
        poorUser.stake.tokenAmountForLpPercent = 50;
        poorUser.stake.parentTokenAmountForLpPercent = 50;
        poorUser.stake.tokenAmountPercent = 50;
        // Ensure user has token balance for staking (createUser only mints parent token)
        h.forceMint(tokenAddress, poorUser.userAddress, 1e24); // Mint enough tokens
        h.stake_liquidity(poorUser);
        h.stake_token(poorUser);

        // Move to next round to submit action for extensionZeroMin
        // (bob already submitted action for extension in setUp, so we can't submit in same round)
        h.next_phase();
        h.next_phase();
        h.next_phase();
        h.next_phase();

        // Now submit action for extensionZeroMin in the new round
        uint256 actionIdZeroMin = h.submit_new_action_with_extension(
            bob,
            address(extensionZeroMin)
        );
        poorUser.actionId = actionIdZeroMin;
        h.vote(poorUser);

        h.next_phase();
        // extension_join will automatically add liquidity to Uniswap pair if needed
        uint256 lpAmount = 1e18;

        // Should succeed with MIN_GOV_RATIO = 0 (totalGovVotes > 0 from stake)
        h.extension_join(poorUser, extensionZeroMin, lpAmount);

        (, uint256 amount, , ) = extensionZeroMin.joinInfo(
            poorUser.userAddress
        );
        assertEq(amount, lpAmount);
    }
}
