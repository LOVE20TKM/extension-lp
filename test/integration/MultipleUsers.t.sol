// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {Test} from "forge-std/Test.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
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
import {
    FIRST_PARENT_TOKEN_FUNDRAISING_GOAL,
    PHASE_BLOCKS
} from "@extension/lib/core/test/Constant.sol";

contract MultipleUsersTest is Test {
    TestExtensionLpHelper public h;
    ExtensionLp public extension;
    address public tokenAddress;
    uint256 public actionId;

    function setUp() public {
        h = new TestExtensionLpHelper();
        tokenAddress = h.firstTokenAddress();

        // Finish launch
        FlowUserParams memory bob = h.createUser(
            "bob",
            tokenAddress,
            FIRST_PARENT_TOKEN_FUNDRAISING_GOAL
        );
        FlowUserParams memory alice = h.createUser(
            "alice",
            tokenAddress,
            FIRST_PARENT_TOKEN_FUNDRAISING_GOAL
        );

        h.launch_contribute(bob);
        h.jump_second_half_min();
        h.launch_contribute(alice);
        h.launch_skip_claim_delay();
        h.launch_claim(bob);
        h.launch_claim(alice);

        extension = h.createExtension(tokenAddress, 2, 0); // MIN_GOV_RATIO = 0 for multi-user tests
    }

    function test_multipleUsers_join() public {
        uint256 numUsers = 5;
        FlowUserParams[] memory users = new FlowUserParams[](numUsers);

        // Create users
        for (uint256 i = 0; i < numUsers; i++) {
            users[i] = h.createUser(
                string(abi.encodePacked("user", Strings.toString(i))),
                tokenAddress,
                FIRST_PARENT_TOKEN_FUNDRAISING_GOAL
            );
        }

        // Stake and vote
        for (uint256 i = 0; i < numUsers; i++) {
            // Ensure stake parameters are set (always set to ensure they're not 0)
            users[i].stake.tokenAmountForLpPercent = 50;
            users[i].stake.parentTokenAmountForLpPercent = 50;
            users[i].stake.tokenAmountPercent = 50;
            // Ensure users have token balance for staking (createUser only mints parent token)
            h.forceMint(tokenAddress, users[i].userAddress, 1e24); // Mint enough tokens
            h.stake_liquidity(users[i]);
            h.stake_token(users[i]);
        }

        // Submit action with extension address as whiteListAddress
        actionId = h.submit_new_action_with_extension(
            users[0],
            address(extension)
        );
        for (uint256 i = 0; i < numUsers; i++) {
            users[i].actionId = actionId;
            h.vote(users[i]);
        }

        // Join
        h.next_phase();
        // extension_join will automatically add liquidity to Uniswap pair if needed
        for (uint256 i = 0; i < numUsers; i++) {
            uint256 lpAmount = 1e18;
            h.extension_join(users[i], extension, lpAmount);
        }

        // Verify all users joined
        for (uint256 i = 0; i < numUsers; i++) {
            (, uint256 amount, , ) = extension.joinInfo(users[i].userAddress);
            assertGt(amount, 0, "User should have joined");
        }

        // Check total joined amount
        uint256 totalJoinedAmount = extension.joinedAmount();
        assertGt(totalJoinedAmount, 0, "Total joined amount should be > 0");
    }

    function test_multipleUsers_rewardDistribution() public {
        uint256 numUsers = 3;
        FlowUserParams[] memory users = new FlowUserParams[](numUsers);

        // Create users
        for (uint256 i = 0; i < numUsers; i++) {
            users[i] = h.createUser(
                string(abi.encodePacked("user", Strings.toString(i))),
                tokenAddress,
                FIRST_PARENT_TOKEN_FUNDRAISING_GOAL
            );
        }

        // Stake and vote
        for (uint256 i = 0; i < numUsers; i++) {
            // Ensure stake parameters are set (always set to ensure they're not 0)
            users[i].stake.tokenAmountForLpPercent = 50;
            users[i].stake.parentTokenAmountForLpPercent = 50;
            users[i].stake.tokenAmountPercent = 50;
            // Ensure users have token balance for staking (createUser only mints parent token)
            h.forceMint(tokenAddress, users[i].userAddress, 1e24); // Mint enough tokens
            h.stake_liquidity(users[i]);
            h.stake_token(users[i]);
        }

        actionId = h.submit_new_action_with_extension(
            users[0],
            address(extension)
        );
        for (uint256 i = 0; i < numUsers; i++) {
            users[i].actionId = actionId;
            h.vote(users[i]);
        }

        // Join with different amounts
        h.next_phase();
        // extension_join will automatically add liquidity to Uniswap pair if needed
        for (uint256 i = 0; i < numUsers; i++) {
            uint256 lpAmount = (1e18 * (i + 1)) / numUsers; // Different amounts
            h.extension_join(users[i], extension, lpAmount);
        }

        // Verify
        h.next_phase();
        for (uint256 i = 0; i < numUsers; i++) {
            h.verify(users[i]);
        }

        // Mint rewards
        h.next_phase();
        h.mint_action_reward_for_extension(users[0], address(extension));

        uint256 round = h.verifyContract().currentRound() - 1;

        // Check rewards for all users
        uint256 totalMintReward = 0;
        uint256 totalBurnReward = 0;

        for (uint256 i = 0; i < numUsers; i++) {
            (uint256 mintReward, uint256 burnReward, bool claimed) = extension
                .rewardByAccount(round, users[i].userAddress);

            assertGt(mintReward, 0, "User should have mint reward");
            assertGe(burnReward, 0, "User should have burn reward >= 0");
            assertFalse(claimed, "Should not be minted before claim");

            totalMintReward += mintReward;
            totalBurnReward += burnReward;
        }

        assertGt(totalMintReward, 0, "Total mint reward should be > 0");
    }

    function test_multipleUsers_differentLpAmounts() public {
        uint256 numUsers = 4;
        FlowUserParams[] memory users = new FlowUserParams[](numUsers);

        // Create users
        for (uint256 i = 0; i < numUsers; i++) {
            users[i] = h.createUser(
                string(abi.encodePacked("user", Strings.toString(i))),
                tokenAddress,
                FIRST_PARENT_TOKEN_FUNDRAISING_GOAL
            );
        }

        // Stake different amounts
        // First user stakes with higher percentage to establish initial liquidity
        users[0].stake.tokenAmountForLpPercent = 50;
        users[0].stake.parentTokenAmountForLpPercent = 50;
        users[0].stake.tokenAmountPercent = 50;
        h.forceMint(tokenAddress, users[0].userAddress, 1e24);
        h.stake_liquidity(users[0]);
        h.stake_token(users[0]);

        // Other users stake with different amounts
        for (uint256 i = 1; i < numUsers; i++) {
            users[i].stake.tokenAmountForLpPercent = 10 + ((i - 1) * 10);
            users[i].stake.parentTokenAmountForLpPercent = 10 + ((i - 1) * 10);
            users[i].stake.tokenAmountPercent = 10 + ((i - 1) * 10);
            // Ensure users have token balance for staking (createUser only mints parent token)
            h.forceMint(tokenAddress, users[i].userAddress, 1e24); // Mint enough tokens
            h.stake_liquidity(users[i]);
            h.stake_token(users[i]);
        }

        actionId = h.submit_new_action_with_extension(
            users[0],
            address(extension)
        );
        for (uint256 i = 0; i < numUsers; i++) {
            users[i].actionId = actionId;
            h.vote(users[i]);
        }

        // Join with fixed LP amounts
        h.next_phase();
        // extension_join will automatically add liquidity to Uniswap pair if needed
        for (uint256 i = 0; i < numUsers; i++) {
            uint256 lpAmount = 1e18;
            h.extension_join(users[i], extension, lpAmount);
        }

        // Check joined amounts
        uint256 totalJoinedAmount = extension.joinedAmount();
        assertGt(totalJoinedAmount, 0, "Total joined amount should be > 0");

        for (uint256 i = 0; i < numUsers; i++) {
            uint256 userJoinedAmount = extension.joinedAmountByAccount(
                users[i].userAddress
            );
            assertGt(userJoinedAmount, 0, "User should have joined amount");
        }
    }

    function test_multipleUsers_withdraw() public {
        uint256 numUsers = 3;
        FlowUserParams[] memory users = new FlowUserParams[](numUsers);

        // Create users
        for (uint256 i = 0; i < numUsers; i++) {
            users[i] = h.createUser(
                string(abi.encodePacked("user", Strings.toString(i))),
                tokenAddress,
                FIRST_PARENT_TOKEN_FUNDRAISING_GOAL
            );
        }

        // Stake and vote
        for (uint256 i = 0; i < numUsers; i++) {
            // Ensure stake parameters are set (always set to ensure they're not 0)
            users[i].stake.tokenAmountForLpPercent = 50;
            users[i].stake.parentTokenAmountForLpPercent = 50;
            users[i].stake.tokenAmountPercent = 50;
            // Ensure users have token balance for staking (createUser only mints parent token)
            h.forceMint(tokenAddress, users[i].userAddress, 1e24); // Mint enough tokens
            h.stake_liquidity(users[i]);
            h.stake_token(users[i]);
        }

        actionId = h.submit_new_action_with_extension(
            users[0],
            address(extension)
        );
        for (uint256 i = 0; i < numUsers; i++) {
            users[i].actionId = actionId;
            h.vote(users[i]);
        }

        // Join
        h.next_phase();
        // extension_join will automatically add liquidity to Uniswap pair if needed
        for (uint256 i = 0; i < numUsers; i++) {
            uint256 lpAmount = 1e18;
            h.extension_join(users[i], extension, lpAmount);
        }

        // Wait for withdrawal
        h.next_phases(7 / PHASE_BLOCKS + 1);

        // Withdraw
        IUniswapV2Pair lpToken = h.getLpToken(tokenAddress);
        for (uint256 i = 0; i < numUsers; i++) {
            uint256 lpBalanceBefore = lpToken.balanceOf(users[i].userAddress);
            h.extension_withdraw(users[i], extension);
            uint256 lpBalanceAfter = lpToken.balanceOf(users[i].userAddress);
            assertGt(
                lpBalanceAfter,
                lpBalanceBefore,
                "Should receive LP tokens back"
            );
        }
    }
}
