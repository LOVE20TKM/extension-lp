// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {Test} from "forge-std/Test.sol";
import {
    TestExtensionLpHelper,
    FlowUserParams
} from "../TestExtensionLpHelper.sol";
import {ExtensionLp} from "../../src/ExtensionLp.sol";
import {ILp, ILpErrors} from "../../src/interface/ILp.sol";
import {ILOVE20Token} from "@core/interfaces/ILOVE20Token.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    IUniswapV2Pair
} from "@core/uniswap-v2-core/interfaces/IUniswapV2Pair.sol";
import {
    FIRST_PARENT_TOKEN_FUNDRAISING_GOAL
} from "@extension/lib/core/test/Constant.sol";

contract GovVotesTest is Test {
    TestExtensionLpHelper public h;
    FlowUserParams public bob;
    FlowUserParams public alice;
    ExtensionLp public extension;
    address public tokenAddress;

    function setUp() public {
        h = new TestExtensionLpHelper();
        (bob, alice) = h.finish_launch();
        tokenAddress = h.firstTokenAddress();

        // Create extension with MIN_GOV_VOTES = 1e18
        extension = h.createExtension(
            tokenAddress,
            2,
            1e18 // MIN_GOV_VOTES
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

    function test_join_revertIfInsufficientGovVotes() public {
        // Create user with insufficient gov votes
        FlowUserParams memory poorUser = h.createUser(
            "poorUser",
            tokenAddress,
            FIRST_PARENT_TOKEN_FUNDRAISING_GOAL
        );

        // Stake but with low amount to get low gov votes
        // Use minimum valid stake amounts (not too low to avoid StakeAmountMustBeSet error)
        poorUser.stake.tokenAmountForLpPercent = 10;
        poorUser.stake.parentTokenAmountForLpPercent = 10;
        poorUser.stake.tokenAmountPercent = 10;
        // Ensure user has token balance for staking (createUser only mints parent token)
        h.forceMint(tokenAddress, poorUser.userAddress, 1e24); // Mint enough tokens
        h.stake_liquidity(poorUser);
        h.stake_token(poorUser);

        // Check gov votes
        uint256 govVotes = h.stakeContract().validGovVotes(
            tokenAddress,
            poorUser.userAddress
        );

        // If gov votes is less than MIN_GOV_VOTES, should revert
        if (govVotes < 1e18) {
            h.next_phase();
            // extension_join will automatically add liquidity to Uniswap pair if needed
            uint256 lpAmount = 1e18;
            IUniswapV2Pair lpToken = h.getLpToken(tokenAddress);

            vm.startPrank(poorUser.userAddress);
            IERC20(address(lpToken)).approve(address(extension), lpAmount);
            vm.expectRevert(ILpErrors.InsufficientGovVotes.selector);
            extension.join(lpAmount, new string[](0));
            vm.stopPrank();
        }
    }

    function test_join_succeedWithExactMinGovVotes() public {
        h.stake_liquidity(bob);
        h.stake_token(bob);
        h.vote(bob);

        // Bob should have enough gov votes from staking
        uint256 govVotes = h.stakeContract().validGovVotes(
            tokenAddress,
            bob.userAddress
        );
        assertGe(govVotes, 1e18, "Bob should have at least MIN_GOV_VOTES");

        h.next_phase();
        // extension_join will automatically add liquidity to Uniswap pair if needed
        uint256 lpAmount = 1e18;
        h.extension_join(bob, extension, lpAmount);

        (uint256 joinedRound, uint256 amount, , ) = extension.joinInfo(
            bob.userAddress
        );
        assertEq(joinedRound, h.joinContract().currentRound());
        assertEq(amount, lpAmount);
    }

    function test_join_succeedWithMoreThanMinGovVotes() public {
        h.stake_liquidity(bob);
        h.stake_token(bob);
        h.vote(bob);

        // Stake more to get more gov votes (in the same phase, just call again)
        h.stake_liquidity(bob);
        h.stake_token(bob);

        uint256 govVotes = h.stakeContract().validGovVotes(
            tokenAddress,
            bob.userAddress
        );
        assertGt(govVotes, 1e18, "Bob should have more than MIN_GOV_VOTES");

        h.next_phase();
        // extension_join will automatically add liquidity to Uniswap pair if needed
        uint256 lpAmount = 1e18;
        h.extension_join(bob, extension, lpAmount);

        (, uint256 amount, , ) = extension.joinInfo(bob.userAddress);
        assertEq(amount, lpAmount);
    }

    function test_join_subsequentJoinsNoGovVotesCheck() public {
        h.stake_liquidity(bob);
        h.stake_token(bob);
        h.vote(bob);

        h.next_phase();
        // extension_join will automatically add liquidity to Uniswap pair if needed
        uint256 lpAmount1 = 1e18;
        // First join - should check gov votes
        h.extension_join(bob, extension, lpAmount1);

        // Second join - should not check gov votes again
        uint256 lpAmount2 = 5e17;
        h.extension_join(bob, extension, lpAmount2);

        (, uint256 totalAmount, , ) = extension.joinInfo(bob.userAddress);
        assertEq(totalAmount, lpAmount1 + lpAmount2);
    }

    function test_immutableVariables_minGovVotes() public view {
        assertEq(
            extension.MIN_GOV_VOTES(),
            1e18,
            "MIN_GOV_VOTES should be 1e18"
        );
    }

    function test_immutableVariables_govRatioMultiplier() public view {
        assertEq(
            extension.GOV_RATIO_MULTIPLIER(),
            2,
            "GOV_RATIO_MULTIPLIER should be 2"
        );
    }
}
