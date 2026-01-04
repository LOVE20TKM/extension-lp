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
import {
    FIRST_PARENT_TOKEN_FUNDRAISING_GOAL
} from "@extension/lib/core/test/Constant.sol";

contract LpConversionTest is Test {
    TestExtensionLpHelper public h;
    FlowUserParams public bob;
    FlowUserParams public alice;
    ExtensionLp public extension;
    address public tokenAddress;

    function setUp() public {
        h = new TestExtensionLpHelper();
        (bob, alice) = h.finish_launch();
        tokenAddress = h.firstTokenAddress();
        extension = h.createExtensionWithDefaults(tokenAddress);
    }

    function test_joinedValue_zeroWhenNoJoins() public view {
        assertEq(
            extension.joinedValue(),
            0,
            "joinedValue should be 0 when no joins"
        );
    }

    function test_joinedValue_singleUser() public {
        h.stake_liquidity(bob);
        h.stake_token(bob);
        bob.actionId = h.submit_new_action_with_extension(
            bob,
            address(extension)
        );
        h.vote(bob);

        h.next_phase();
        // extension_join will automatically add liquidity to Uniswap pair if needed
        uint256 lpAmount = 1e18;
        h.extension_join(bob, extension, lpAmount);

        IUniswapV2Pair lpToken = h.getLpToken(tokenAddress);

        uint256 joinedValue = extension.joinedValue();
        assertGt(joinedValue, 0, "joinedValue should be > 0 after join");

        // Calculate expected value
        (uint112 reserve0, uint112 reserve1, ) = lpToken.getReserves();
        address pairToken0 = lpToken.token0();
        uint256 tokenReserve = (pairToken0 == tokenAddress)
            ? uint256(reserve0)
            : uint256(reserve1);
        uint256 totalLp = lpToken.totalSupply();
        uint256 expectedValue = (lpAmount * tokenReserve * 2) / totalLp;

        // Allow small difference due to rounding
        uint256 diff = joinedValue > expectedValue
            ? joinedValue - expectedValue
            : expectedValue - joinedValue;
        assertLt(
            diff,
            expectedValue / 1000,
            "joinedValue should match calculation"
        );
    }

    function test_joinedValueByAccount() public {
        h.stake_liquidity(bob);
        h.stake_token(bob);
        bob.actionId = h.submit_new_action_with_extension(
            bob,
            address(extension)
        );
        h.vote(bob);

        h.next_phase();
        // extension_join will automatically add liquidity to Uniswap pair if needed
        uint256 bobLp = 1e18;
        h.extension_join(bob, extension, bobLp);

        IUniswapV2Pair lpToken = h.getLpToken(tokenAddress);

        uint256 bobJoinedValue = extension.joinedValueByAccount(
            bob.userAddress
        );
        assertGt(bobJoinedValue, 0, "Bob's joinedValue should be > 0");

        // Calculate expected value
        (uint112 reserve0, uint112 reserve1, ) = lpToken.getReserves();
        address pairToken0 = lpToken.token0();
        uint256 tokenReserve = (pairToken0 == tokenAddress)
            ? uint256(reserve0)
            : uint256(reserve1);
        uint256 totalLp = lpToken.totalSupply();
        uint256 expectedValue = (bobLp * tokenReserve * 2) / totalLp;

        uint256 diff = bobJoinedValue > expectedValue
            ? bobJoinedValue - expectedValue
            : expectedValue - bobJoinedValue;
        assertLt(
            diff,
            expectedValue / 1000,
            "joinedValueByAccount should match calculation"
        );
    }

    function test_joinedValue_multipleUsers() public {
        h.stake_liquidity(bob);
        h.stake_token(bob);
        h.stake_liquidity(alice);
        h.stake_token(alice);
        bob.actionId = h.submit_new_action_with_extension(
            bob,
            address(extension)
        );
        alice.actionId = bob.actionId;
        h.vote(bob);
        h.vote(alice);

        h.next_phase();
        // extension_join will automatically add liquidity to Uniswap pair if needed
        uint256 bobLp = 1e18;
        uint256 aliceLp = 1e18;

        h.extension_join(bob, extension, bobLp);
        h.extension_join(alice, extension, aliceLp);

        uint256 totalJoinedValue = extension.joinedValue();
        uint256 bobJoinedValue = extension.joinedValueByAccount(
            bob.userAddress
        );
        uint256 aliceJoinedValue = extension.joinedValueByAccount(
            alice.userAddress
        );

        assertGt(totalJoinedValue, 0, "Total joinedValue should be > 0");
        assertGt(bobJoinedValue, 0, "Bob's joinedValue should be > 0");
        assertGt(aliceJoinedValue, 0, "Alice's joinedValue should be > 0");

        // Total should equal sum of individual values
        uint256 sum = bobJoinedValue + aliceJoinedValue;
        uint256 diff = totalJoinedValue > sum
            ? totalJoinedValue - sum
            : sum - totalJoinedValue;
        assertLt(
            diff,
            totalJoinedValue / 1000,
            "Total should equal sum of individual values"
        );
    }

    function test_joinedValue_afterReservesChange() public {
        h.stake_liquidity(bob);
        h.stake_token(bob);
        bob.actionId = h.submit_new_action_with_extension(
            bob,
            address(extension)
        );
        h.vote(bob);

        h.next_phase();
        // extension_join will automatically add liquidity to Uniswap pair if needed
        uint256 lpAmount = 1e18;
        h.extension_join(bob, extension, lpAmount);

        IUniswapV2Pair lpToken = h.getLpToken(tokenAddress);

        // Add more liquidity to change reserves
        h.stake_liquidity(alice);
        h.stake_token(alice);

        uint256 joinedValueAfter = extension.joinedValue();

        // joinedValue should change when reserves change
        // The ratio should remain approximately the same
        (uint112 reserve0, uint112 reserve1, ) = lpToken.getReserves();
        address pairToken0 = lpToken.token0();
        uint256 tokenReserve = (pairToken0 == tokenAddress)
            ? uint256(reserve0)
            : uint256(reserve1);
        uint256 totalLp = lpToken.totalSupply();
        uint256 expectedValue = (lpAmount * tokenReserve * 2) / totalLp;

        uint256 diff = joinedValueAfter > expectedValue
            ? joinedValueAfter - expectedValue
            : expectedValue - joinedValueAfter;
        assertLt(
            diff,
            expectedValue / 1000,
            "joinedValue should match new reserves"
        );
    }
}
