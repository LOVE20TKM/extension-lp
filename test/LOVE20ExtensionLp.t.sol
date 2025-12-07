// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {Test, console} from "forge-std/Test.sol";
import {LOVE20ExtensionLp} from "../src/LOVE20ExtensionLp.sol";
import {LOVE20ExtensionFactoryLp} from "../src/LOVE20ExtensionFactoryLp.sol";
import {ILOVE20ExtensionLp} from "../src/interface/ILOVE20ExtensionLp.sol";
import {
    ILOVE20ExtensionTokenJoinAuto
} from "@extension/src/interface/ILOVE20ExtensionTokenJoinAuto.sol";
import {
    ILOVE20ExtensionFactoryLp
} from "../src/interface/ILOVE20ExtensionFactoryLp.sol";
import {ILOVE20Extension} from "@extension/src/interface/ILOVE20Extension.sol";
import {
    ILOVE20ExtensionFactory
} from "@extension/src/interface/ILOVE20ExtensionFactory.sol";
import {
    ILOVE20ExtensionCenter
} from "@extension/src/interface/ILOVE20ExtensionCenter.sol";
import {LOVE20ExtensionCenter} from "@extension/src/LOVE20ExtensionCenter.sol";
import {
    IUniswapV2Pair
} from "@core/uniswap-v2-core/interfaces/IUniswapV2Pair.sol";
import {ITokenJoin} from "@extension/src/interface/base/ITokenJoin.sol";

// Import mock contracts
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockUniswapV2Factory} from "./mocks/MockUniswapV2Factory.sol";
import {MockUniswapV2Pair} from "./mocks/MockUniswapV2Pair.sol";
import {MockStake} from "./mocks/MockStake.sol";
import {MockJoin} from "./mocks/MockJoin.sol";
import {MockVerify} from "./mocks/MockVerify.sol";
import {MockMint} from "./mocks/MockMint.sol";
import {MockSubmit} from "./mocks/MockSubmit.sol";
import {MockLaunch} from "./mocks/MockLaunch.sol";
import {MockVote} from "./mocks/MockVote.sol";
import {MockRandom} from "./mocks/MockRandom.sol";

/**
 * @title LOVE20ExtensionLp Test Suite
 * @notice Tests for LP-specific functionality
 * @dev Basic join/withdraw tests are covered in lib/extension/test/LOVE20ExtensionSimpleJoin.t.sol
 *      This test suite focuses on LP-specific features:
 *      - LP token validation
 *      - LP to token conversion (joinedValue)
 *      - govRatioMultiplier in score calculation
 *      - Factory with LP-specific parameters
 */
contract LOVE20ExtensionLpTest is Test {
    LOVE20ExtensionFactoryLp public factory;
    LOVE20ExtensionLp public extension;
    LOVE20ExtensionCenter public center;
    MockERC20 public token;
    MockUniswapV2Pair public joinToken;
    MockStake public stake;
    MockJoin public join;
    MockVerify public verify;
    MockMint public mint;
    MockSubmit public submit;
    MockLaunch public launch;
    MockVote public vote;
    MockRandom public random;

    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public user3 = address(0x3);

    uint256 constant ACTION_ID = 1;
    uint256 constant WAITING_BLOCKS = 7;
    uint256 constant GOV_RATIO_MULTIPLIER = 2;
    uint256 constant MIN_GOV_VOTES = 1e18;
    uint256 constant LP_RATIO_PRECISION = 1000; // 0.1% minimum LP ratio

    function setUp() public {
        // Deploy mock contracts
        token = new MockERC20();
        MockUniswapV2Factory uniswapFactory = new MockUniswapV2Factory();
        // Create a Pair for token and another token (e.g., WETH)
        MockERC20 otherToken = new MockERC20();
        joinToken = MockUniswapV2Pair(
            uniswapFactory.createPair(address(token), address(otherToken))
        );
        stake = new MockStake();
        join = new MockJoin();
        verify = new MockVerify();
        mint = new MockMint();
        submit = new MockSubmit();
        launch = new MockLaunch();
        vote = new MockVote();
        random = new MockRandom();

        // Deploy real LOVE20ExtensionCenter
        center = new LOVE20ExtensionCenter(
            address(uniswapFactory),
            address(launch),
            address(stake),
            address(submit),
            address(vote),
            address(join),
            address(verify),
            address(mint),
            address(random)
        );

        // Deploy factory
        factory = new LOVE20ExtensionFactoryLp(address(center));

        // Mint and approve tokens for extension creation
        token.mint(address(this), 1e18);
        token.approve(address(factory), 1e18);

        // Create extension
        extension = LOVE20ExtensionLp(
            factory.createExtension(
                address(token),
                address(joinToken),
                WAITING_BLOCKS,
                GOV_RATIO_MULTIPLIER,
                MIN_GOV_VOTES,
                LP_RATIO_PRECISION
            )
        );

        // Register factory to center (needs canSubmit permission)
        submit.setCanSubmit(address(token), address(this), true);
        center.addFactory(address(token), address(factory));

        // Set action info whiteListAddress to extension address
        submit.setActionInfo(address(token), ACTION_ID, address(extension));

        // Set vote mock for auto-initialization
        vote.setVotedActionIds(address(token), join.currentRound(), ACTION_ID);

        // Setup users with join tokens
        joinToken.mint(user1, 100e18);
        joinToken.mint(user2, 200e18);
        joinToken.mint(user3, 300e18);

        // Set initial total supply for joinToken (for ratio calculations)
        // Total supply = initial minted amounts + any additional
        joinToken.mint(address(0x1), 1000e18); // Add to total supply for ratio calculation

        // Set Pair reserves for LP to token conversion
        // Set reserves: token reserves = 10000e18, otherToken reserves = 10000e18
        // This allows LP to token conversion to work correctly
        // The actual mapping (token0/token1) will be determined by pair.token0() in the contract
        joinToken.setReserves(10000e18, 10000e18);

        // Approve extension to spend join tokens
        vm.prank(user1);
        joinToken.approve(address(extension), type(uint256).max);
        vm.prank(user2);
        joinToken.approve(address(extension), type(uint256).max);
        vm.prank(user3);
        joinToken.approve(address(extension), type(uint256).max);

        // Setup gov votes
        stake.setGovVotesNum(address(token), 1000e18);
        stake.setValidGovVotes(address(token), user1, 100e18);
        stake.setValidGovVotes(address(token), user2, 200e18);
        stake.setValidGovVotes(address(token), user3, 300e18);

        // Mint tokens to extension for rewards
        token.mint(address(extension), 10000e18);
    }

    // ============================================
    // Initialization Tests (LP-specific validation)
    // ============================================

    function test_Initialize_RevertIfInvalidJoinTokenAddress() public {
        // Deploy new extension with invalid joinToken (not a Pair)
        // Must create through factory to register it
        MockERC20 invalidStakeToken = new MockERC20();

        // Creation should fail because invalidStakeToken is not a Pair
        // _validateJoinToken is now called in constructor
        vm.expectRevert(ITokenJoin.InvalidJoinTokenAddress.selector);
        factory.createExtension(
            address(token),
            address(invalidStakeToken),
            WAITING_BLOCKS,
            GOV_RATIO_MULTIPLIER,
            MIN_GOV_VOTES,
            LP_RATIO_PRECISION
        );
    }

    function test_Initialize_RevertIfStakeTokenNotPairWithToken() public {
        // Create a Pair that doesn't include token using the same factory as center
        MockERC20 token1 = new MockERC20();
        MockERC20 token2 = new MockERC20();
        // Use the same factory that was used in setUp
        address uniswapFactoryAddr = center.uniswapV2FactoryAddress();
        MockUniswapV2Factory uniswapFactory = MockUniswapV2Factory(
            uniswapFactoryAddr
        );
        MockUniswapV2Pair wrongPair = MockUniswapV2Pair(
            uniswapFactory.createPair(address(token1), address(token2))
        );

        // Creation should fail because wrongPair doesn't include token
        // _validateJoinToken is now called in constructor
        vm.expectRevert(ITokenJoin.InvalidJoinTokenAddress.selector);
        factory.createExtension(
            address(token),
            address(wrongPair),
            WAITING_BLOCKS,
            GOV_RATIO_MULTIPLIER,
            MIN_GOV_VOTES,
            LP_RATIO_PRECISION
        );
    }

    // ============================================
    // View Function Tests (LP-specific)
    // ============================================

    function test_ImmutableVariables_GovRatioMultiplier() public view {
        // Test LP-specific parameter
        assertEq(extension.govRatioMultiplier(), GOV_RATIO_MULTIPLIER);
        // Basic immutable variables are tested in base contract
        assertEq(extension.joinTokenAddress(), address(joinToken));
        assertEq(extension.waitingBlocks(), WAITING_BLOCKS);
    }

    function test_IsJoinedValueCalculated() public view {
        // LP extension should calculate joined value
        assertTrue(extension.isJoinedValueCalculated());
    }

    // ============================================
    // LP to Token Conversion Tests (joinedValue)
    // ============================================
    // Note: Basic join/unjoin/withdraw functionality is tested in base contract

    function test_JoinedValue() public {
        vm.prank(user1);
        extension.join(100e18, new string[](0));

        // joinedValue should return tokenAddress amount, not LP token amount
        // Get actual LP supply after join (join transfers LP tokens to extension)
        IUniswapV2Pair pair = IUniswapV2Pair(address(joinToken));
        uint256 totalLpSupply = pair.totalSupply();
        uint256 joindLpAmount = 100e18;

        // Get token reserve (token is either token0 or token1)
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        address pairToken0 = pair.token0();
        uint256 tokenReserve = (pairToken0 == address(token))
            ? uint256(reserve0)
            : uint256(reserve1);

        // Calculate expected token amount: (joindLpAmount * tokenReserve) / totalLpSupply
        uint256 expectedTokenAmount = (joindLpAmount * tokenReserve) /
            totalLpSupply;
        assertEq(extension.joinedValue(), expectedTokenAmount);
    }

    function test_JoinedValueByAccount() public {
        vm.prank(user1);
        extension.join(50e18, new string[](0));

        vm.prank(user2);
        extension.join(100e18, new string[](0));

        // joinedValueByAccount should return tokenAddress amount, not LP token amount
        // Get actual LP supply after both joins
        IUniswapV2Pair pair = IUniswapV2Pair(address(joinToken));
        uint256 totalLpSupply = pair.totalSupply();

        // Get token reserve (token is either token0 or token1)
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        address pairToken0 = pair.token0();
        uint256 tokenReserve = (pairToken0 == address(token))
            ? uint256(reserve0)
            : uint256(reserve1);

        // Calculate expected token amounts
        uint256 expectedTokenAmount1 = (50e18 * tokenReserve) / totalLpSupply;
        uint256 expectedTokenAmount2 = (100e18 * tokenReserve) / totalLpSupply;
        assertEq(extension.joinedValueByAccount(user1), expectedTokenAmount1);
        assertEq(extension.joinedValueByAccount(user2), expectedTokenAmount2);
    }

    // ============================================
    // Score Calculation Tests (LP-specific with govRatioMultiplier)
    // ============================================
    // Note: Basic score calculation is tested in base contract
    // This section tests LP-specific scoring logic with govRatioMultiplier

    function test_CalculateScores_DirectCall_SingleUser() public {
        // Setup: user1 joins 100e18 LP
        vm.prank(user1);
        extension.join(100e18, new string[](0));

        // Direct call to calculateScores
        (uint256 totalScore, uint256[] memory scores) = extension
            .calculateScores();

        // Verify results
        assertEq(scores.length, 1, "Should have 1 score");
        assertTrue(totalScore > 0, "Total score should be greater than 0");
        assertEq(
            totalScore,
            scores[0],
            "Total score should equal single score"
        );

        // Expected calculation:
        // Total LP: 1600e18 (1000e18 in pair + 100e18 user1 + 200e18 user2 + 300e18 user3)
        // User LP: 100e18
        // LP ratio (with lpRatioPrecision): (100e18 * 1000) / 1600e18 = 62.5 (rounded down to 62)
        // Total gov votes: 1000e18, User gov votes: 100e18
        // Gov ratio (with lpRatioPrecision): (100e18 * 1000 * 2) / 1000e18 = 200
        // Score: min(62, 200) = 62
        assertEq(scores[0], 62, "Score should be 62");
        assertEq(totalScore, 62, "Total score should be 62");
    }

    function test_CalculateScores_DirectCall_MultipleUsers() public {
        // Setup: multiple users join different amounts
        vm.prank(user1);
        extension.join(100e18, new string[](0));

        vm.prank(user2);
        extension.join(200e18, new string[](0));

        vm.prank(user3);
        extension.join(300e18, new string[](0));

        // Direct call to calculateScores
        (uint256 totalScore, uint256[] memory scores) = extension
            .calculateScores();

        // Verify results
        assertEq(scores.length, 3, "Should have 3 scores");
        assertTrue(totalScore > 0, "Total score should be greater than 0");

        // Expected calculations (Total LP: 1600e18, LP_RATIO_PRECISION = 1000):
        // User1: lpRatio = (100e18 * 1000) / 1600e18 = 62, govRatio = (100e18 * 1000 * 2) / 1000e18 = 200, score = 62
        // User2: lpRatio = (200e18 * 1000) / 1600e18 = 125, govRatio = (200e18 * 1000 * 2) / 1000e18 = 400, score = 125
        // User3: lpRatio = (300e18 * 1000) / 1600e18 = 187, govRatio = (300e18 * 1000 * 2) / 1000e18 = 600, score = 187
        assertEq(scores[0], 62, "User1 score should be 62");
        assertEq(scores[1], 125, "User2 score should be 125");
        assertEq(scores[2], 187, "User3 score should be 187");
        assertEq(totalScore, 374, "Total score should be sum of all scores");
    }

    function test_CalculateScores_LpRatioIsLimiting() public {
        // Test where user has less LP ratio than gov ratio
        vm.prank(user1);
        extension.join(50e18, new string[](0));

        // Total LP: 1600e18, User LP: 50e18, LP_RATIO_PRECISION = 1000
        // LP ratio: (50e18 * 1000) / 1600e18 = 31.25 (rounded down to 31)
        // User1 has 100e18 gov votes (10% of 1000e18 total)
        // Gov ratio: (100e18 * 1000 * 2) / 1000e18 = 200
        // Score should be limited by LP ratio (min) = 31

        (, uint256[] memory scores) = extension.calculateScores();

        assertEq(scores.length, 1, "Should have 1 score");
        // Score should be limited by LP ratio
        assertEq(scores[0], 31, "Score should be limited by LP ratio");
    }

    function test_CalculateScore_DirectCall_ExistingAccount() public {
        // Setup: join with user1
        vm.prank(user1);
        extension.join(100e18, new string[](0));

        vm.prank(user2);
        extension.join(200e18, new string[](0));

        // Direct call to calculateScore for user1
        (uint256 total, uint256 score) = extension.calculateScore(user1);

        // Verify results
        assertTrue(total > 0, "Total should be greater than 0");
        assertTrue(score > 0, "Score should be greater than 0");
        // User1: lpRatio = 62, govRatio = 200, score = 62
        // User2: lpRatio = 125, govRatio = 400, score = 125
        // Total: 187
        assertEq(score, 62, "User1 score should be 62");
        assertEq(total, 187, "Total score should be 187");
    }

    function test_CalculateScore_DirectCall_NonExistentAccount() public {
        // Setup: join with user1 and user2
        vm.prank(user1);
        extension.join(100e18, new string[](0));

        vm.prank(user2);
        extension.join(200e18, new string[](0));

        // Direct call to calculateScore for user3 (who hasn't joind)
        (uint256 total, uint256 score) = extension.calculateScore(user3);

        // Verify results
        assertTrue(total > 0, "Total should be greater than 0");
        assertEq(score, 0, "Score for non-existent account should be 0");
        assertEq(total, 187, "Total should still be calculated");
    }

    function test_CalculateScore_DirectCall_MultipleUsers() public {
        // Setup: multiple users join
        vm.prank(user1);
        extension.join(100e18, new string[](0));

        vm.prank(user2);
        extension.join(200e18, new string[](0));

        vm.prank(user3);
        extension.join(300e18, new string[](0));

        // Test each user's score
        (uint256 total1, uint256 score1) = extension.calculateScore(user1);
        assertEq(score1, 62, "User1 score should be 62");
        assertEq(total1, 374, "Total should be 374");

        (uint256 total2, uint256 score2) = extension.calculateScore(user2);
        assertEq(score2, 125, "User2 score should be 125");
        assertEq(total2, 374, "Total should be 374");

        (uint256 total3, uint256 score3) = extension.calculateScore(user3);
        assertEq(score3, 187, "User3 score should be 187");
        assertEq(total3, 374, "Total should be 374");

        // Verify sum
        assertEq(
            score1 + score2 + score3,
            total1,
            "Sum of scores should equal total"
        );
    }

    function test_CalculateScore_EmptyAccounts() public view {
        // No accounts, call calculateScore
        (uint256 total, uint256 score) = extension.calculateScore(user1);

        assertEq(total, 0, "Total should be 0 with no accounts");
        assertEq(score, 0, "Score should be 0 with no accounts");
    }

    // ============================================
    // Integration Test - Verify Score Calculation with Rewards
    // ============================================
    // Note: Basic claim reward tests are in base contract
    // This test verifies that LP-specific scoring integrates correctly with rewards

    function test_JoinedValue_ZeroWhenNoStakes() public view {
        // LP-specific: verify joinedValue is 0 when no joins
        assertEq(extension.joinedValue(), 0);
    }

    function test_ScoreCalculation_WithGovRatioMultiplier() public {
        // Test LP-specific scoring with govRatioMultiplier
        vm.prank(user1);
        extension.join(50e18, new string[](0));

        // Set gov votes
        stake.setValidGovVotes(address(token), user1, 10e18);

        (uint256 total, uint256 score) = extension.calculateScore(user1);

        // Verify score is calculated with govRatioMultiplier
        assertTrue(score > 0);
        assertTrue(total > 0);
    }

    // ============================================
    // Factory Tests
    // ============================================

    function test_Factory_CreateExtension() public {
        token.mint(address(this), 1e18);
        token.approve(address(factory), 1e18);
        address newExtension = factory.createExtension(
            address(token),
            address(joinToken),
            WAITING_BLOCKS,
            GOV_RATIO_MULTIPLIER,
            MIN_GOV_VOTES,
            LP_RATIO_PRECISION
        );

        assertTrue(factory.exists(newExtension));
        assertEq(factory.extensionsCount(), 2);
    }

    function test_Factory_Extensions() public {
        // Create multiple extensions with valid LP pairs
        MockERC20 otherToken2 = new MockERC20();
        address uniswapFactoryAddr = center.uniswapV2FactoryAddress();
        MockUniswapV2Factory uniswapFactory = MockUniswapV2Factory(
            uniswapFactoryAddr
        );
        MockUniswapV2Pair joinToken2 = MockUniswapV2Pair(
            uniswapFactory.createPair(address(token), address(otherToken2))
        );

        token.mint(address(this), 1e18);
        token.approve(address(factory), 1e18);
        address extension2 = factory.createExtension(
            address(token),
            address(joinToken2),
            WAITING_BLOCKS,
            GOV_RATIO_MULTIPLIER,
            MIN_GOV_VOTES,
            LP_RATIO_PRECISION
        );

        address[] memory exts = factory.extensions();
        assertEq(exts.length, 2);
        assertEq(exts[0], address(extension));
        assertEq(exts[1], extension2);
    }

    function test_Factory_ExtensionsAtIndex() public {
        // Create another extension with valid LP pair
        MockERC20 otherToken2 = new MockERC20();
        address uniswapFactoryAddr = center.uniswapV2FactoryAddress();
        MockUniswapV2Factory uniswapFactory = MockUniswapV2Factory(
            uniswapFactoryAddr
        );
        MockUniswapV2Pair joinToken2 = MockUniswapV2Pair(
            uniswapFactory.createPair(address(token), address(otherToken2))
        );

        token.mint(address(this), 1e18);
        token.approve(address(factory), 1e18);
        address extension2 = factory.createExtension(
            address(token),
            address(joinToken2),
            WAITING_BLOCKS,
            GOV_RATIO_MULTIPLIER,
            MIN_GOV_VOTES,
            LP_RATIO_PRECISION
        );

        assertEq(factory.extensionsAtIndex(0), address(extension));
        assertEq(factory.extensionsAtIndex(1), extension2);
    }

    function test_Factory_ExtensionParams() public {
        // First trigger auto-initialization by joining
        vm.prank(user1);
        joinToken.approve(address(extension), type(uint256).max);
        vm.prank(user1);
        extension.join(10e18, new string[](0));

        (
            address tokenAddr,
            address joinTokenAddr,
            uint256 waitingBlocks,
            uint256 govRatioMult,
            uint256 minGovVotesVal,
            uint256 lpRatioPrecision
        ) = factory.extensionParams(address(extension));

        assertEq(tokenAddr, address(token), "tokenAddr mismatch");
        assertEq(joinTokenAddr, address(joinToken), "joinTokenAddr mismatch");
        assertEq(waitingBlocks, WAITING_BLOCKS, "waitingBlocks mismatch");
        assertEq(govRatioMult, GOV_RATIO_MULTIPLIER, "govRatioMult mismatch");
        assertEq(minGovVotesVal, MIN_GOV_VOTES, "minGovVotesVal mismatch");
        assertEq(
            lpRatioPrecision,
            LP_RATIO_PRECISION,
            "lpRatioPrecision mismatch"
        );

        // tokenAddress and actionId are now stored in extension itself after initialization
        assertEq(
            extension.tokenAddress(),
            address(token),
            "tokenAddr mismatch"
        );
        assertEq(extension.actionId(), ACTION_ID, "actionId mismatch");
    }

    function test_Factory_ExtensionParams_NonExistent() public view {
        // Query params for non-existent extension
        (
            address tokenAddr,
            address joinTokenAddr,
            uint256 waitingBlocks,
            uint256 govRatioMult,
            uint256 minGovVotesVal,
            uint256 lpRatioPrecision
        ) = factory.extensionParams(address(0x999));

        // Should return zero values
        assertEq(tokenAddr, address(0));
        assertEq(joinTokenAddr, address(0));
        assertEq(waitingBlocks, 0);
        assertEq(govRatioMult, 0);
        assertEq(minGovVotesVal, 0);
        assertEq(lpRatioPrecision, 0);
    }

    function test_Factory_Center() public view {
        assertEq(factory.center(), address(center));
    }

    function test_Factory_RevertIfInvalidJoinTokenAddress() public {
        vm.expectRevert(
            ILOVE20ExtensionFactoryLp.InvalidJoinTokenAddress.selector
        );
        factory.createExtension(
            address(token),
            address(0),
            WAITING_BLOCKS,
            GOV_RATIO_MULTIPLIER,
            MIN_GOV_VOTES,
            LP_RATIO_PRECISION
        );
    }

    // ============================================
    // LP Ratio Precision Tests
    // ============================================

    function test_Join_RevertIfInsufficientLpRatio() public {
        // LP_RATIO_PRECISION = 1000 means minimum ratio is 1/1000 = 0.1%
        // Total LP supply = 1600e18
        // Minimum required LP = 1600e18 / 1000 = 1.6e18
        // Try to join with less than minimum

        // user1 tries to join with 1e18 (less than 1.6e18)
        vm.prank(user1);
        vm.expectRevert(ILOVE20ExtensionLp.InsufficientLpRatio.selector);
        extension.join(1e18, new string[](0));
    }

    function test_Join_SucceedWithSufficientLpRatio() public {
        // LP_RATIO_PRECISION = 1000 means minimum ratio is 1/1000 = 0.1%
        // Total LP supply = 1600e18
        // Minimum required LP = 1600e18 / 1000 = 1.6e18

        // user1 joins with exactly 1.6e18 (should succeed)
        uint256 minRequired = (joinToken.totalSupply() +
            LP_RATIO_PRECISION -
            1) / LP_RATIO_PRECISION;
        vm.prank(user1);
        extension.join(minRequired, new string[](0));

        // Verify join succeeded
        assertEq(extension.totalJoinedAmount(), minRequired);
    }

    function test_Join_NoRestrictionWhenLpRatioPrecisionIsZero() public {
        // Create an extension with lpRatioPrecision = 0 (no restriction)
        token.mint(address(this), 1e18);
        token.approve(address(factory), 1e18);
        address newExtensionAddr = factory.createExtension(
            address(token),
            address(joinToken),
            WAITING_BLOCKS,
            GOV_RATIO_MULTIPLIER,
            MIN_GOV_VOTES,
            0 // No LP ratio restriction
        );

        // Setup for auto-initialization
        submit.setActionInfo(address(token), ACTION_ID + 100, newExtensionAddr);
        vote.setVotedActionIds(
            address(token),
            join.currentRound(),
            ACTION_ID + 100
        );
        token.mint(newExtensionAddr, 1e18);

        LOVE20ExtensionLp newExtension = LOVE20ExtensionLp(newExtensionAddr);

        // Approve
        vm.prank(user1);
        joinToken.approve(address(newExtension), type(uint256).max);

        // user1 can join with any amount, even very small
        vm.prank(user1);
        newExtension.join(1, new string[](0)); // Join with just 1 wei

        // Verify join succeeded
        assertEq(newExtension.totalJoinedAmount(), 1);
    }

    function test_ImmutableVariables_LpRatioPrecision() public view {
        assertEq(extension.lpRatioPrecision(), LP_RATIO_PRECISION);
    }

    // ============================================
    // Min Gov Votes Tests (LP-specific)
    // ============================================

    function test_Join_RevertIfInsufficientGovVotes() public {
        // Create a user with insufficient gov votes
        address poorUser = address(0x999);
        joinToken.mint(poorUser, 1000e18);
        vm.prank(poorUser);
        joinToken.approve(address(extension), type(uint256).max);

        // Set gov votes below MIN_GOV_VOTES (1e18)
        stake.setValidGovVotes(address(token), poorUser, MIN_GOV_VOTES - 1);

        // Try to join should fail
        vm.prank(poorUser);
        vm.expectRevert(ILOVE20ExtensionLp.InsufficientGovVotes.selector);
        extension.join(100e18, new string[](0));
    }

    function test_Join_SucceedWithExactMinGovVotes() public {
        // Create a user with exactly MIN_GOV_VOTES
        address minUser = address(0x888);
        joinToken.mint(minUser, 1000e18);
        vm.prank(minUser);
        joinToken.approve(address(extension), type(uint256).max);

        // Set gov votes exactly at MIN_GOV_VOTES (1e18)
        stake.setValidGovVotes(address(token), minUser, MIN_GOV_VOTES);

        // Join should succeed
        vm.prank(minUser);
        extension.join(100e18, new string[](0));

        // Verify join succeeded
        (uint256 joinedRound, uint256 amount, , ) = extension.joinInfo(minUser);
        assertEq(joinedRound, join.currentRound());
        assertEq(amount, 100e18);
    }

    function test_Join_SucceedWithMoreThanMinGovVotes() public {
        // Create a user with more than MIN_GOV_VOTES
        address richUser = address(0x777);
        joinToken.mint(richUser, 1000e18);
        vm.prank(richUser);
        joinToken.approve(address(extension), type(uint256).max);

        // Set gov votes higher than MIN_GOV_VOTES
        stake.setValidGovVotes(address(token), richUser, MIN_GOV_VOTES * 10);

        // Join should succeed
        vm.prank(richUser);
        extension.join(100e18, new string[](0));

        // Verify join succeeded
        (, uint256 amount, , ) = extension.joinInfo(richUser);
        assertEq(amount, 100e18);
    }

    function test_ImmutableVariables_MinGovVotes() public view {
        assertEq(extension.minGovVotes(), MIN_GOV_VOTES);
    }
}
