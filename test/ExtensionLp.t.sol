// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {Test, console} from "forge-std/Test.sol";
import {ExtensionLp} from "../src/ExtensionLp.sol";
import {ExtensionLpFactory} from "../src/ExtensionLpFactory.sol";
import {ILp, ILpErrors} from "../src/interface/ILp.sol";
import {ILpFactory, ILpFactoryErrors} from "../src/interface/ILpFactory.sol";
import {
    IExtensionFactory
} from "@extension/src/interface/IExtensionFactory.sol";
import {IExtensionCenter} from "@extension/src/interface/IExtensionCenter.sol";
import {ExtensionCenter} from "@extension/src/ExtensionCenter.sol";
import {
    IUniswapV2Pair
} from "@core/uniswap-v2-core/interfaces/IUniswapV2Pair.sol";
import {
    ITokenJoin,
    ITokenJoinErrors
} from "@extension/src/interface/ITokenJoin.sol";

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
 * @title ExtensionLp Test Suite
 * @notice Tests for LP-specific functionality
 * @dev This test suite focuses on LP-specific features:
 *      - LP token validation
 *      - govRatioMultiplier in reward calculation
 *      - rewardInfoByAccount with mint/burn rewards
 *      - Factory with LP-specific parameters
 */
contract ExtensionLpTest is Test {
    ExtensionLpFactory public factory;
    ExtensionLp public extension;
    ExtensionCenter public center;
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
    uint256 constant GOV_RATIO_MULTIPLIER = 2;
    uint256 constant MIN_GOV_RATIO = 1e17; // 10%

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

        // Deploy real ExtensionCenter
        center = new ExtensionCenter(
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
        factory = new ExtensionLpFactory(address(center));

        // Set token as LOVE20 token in launch mock
        launch.setLOVE20Token(address(token), true);

        // Mint and approve tokens for extension creation
        token.mint(address(this), 1e18);
        token.approve(address(factory), 1e18);

        // Create extension
        extension = ExtensionLp(
            factory.createExtension(
                address(token),
                address(joinToken),
                GOV_RATIO_MULTIPLIER,
                MIN_GOV_RATIO
            )
        );

        // Setup submit permissions (mock only)
        submit.setCanSubmit(address(token), address(this), true);

        // Set action info whiteListAddress to extension address
        submit.setActionInfo(address(token), ACTION_ID, address(extension));

        // Set action author to extension creator (address(this) is the creator)
        submit.setActionAuthor(address(token), ACTION_ID, address(this));

        // Set vote mock for auto-initialization
        vote.setVotedActionIds(address(token), join.currentRound(), ACTION_ID);

        // Setup users with join tokens
        joinToken.mint(user1, 100e18);
        joinToken.mint(user2, 200e18);
        joinToken.mint(user3, 300e18);

        // Set initial total supply for joinToken (for ratio calculations)
        joinToken.mint(address(0x1), 1000e18);

        // Set Pair reserves
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

        // Setup block configuration for join contract
        // Set originBlocks to 0 and phaseBlocks to 100
        // Round 0: blocks 0-99, Round 1: blocks 100-199, etc.
        join.setOriginBlocks(0);
        join.setPhaseBlocks(100);

        // Set block.number to be at the start of round 1 (block 100)
        // This ensures users join at the start of the round, so blockRatio = 1
        vm.roll(100);
    }

    // ============================================
    // Initialization Tests (LP-specific validation)
    // ============================================

    function test_Initialize_RevertIfInvalidJoinTokenAddress() public {
        MockERC20 invalidStakeToken = new MockERC20();

        vm.expectRevert(ILpFactoryErrors.InvalidJoinTokenFactory.selector);
        factory.createExtension(
            address(token),
            address(invalidStakeToken),
            GOV_RATIO_MULTIPLIER,
            MIN_GOV_RATIO
        );
    }

    function test_Initialize_RevertIfStakeTokenNotPairWithToken() public {
        MockERC20 token1 = new MockERC20();
        MockERC20 token2 = new MockERC20();
        address uniswapFactoryAddr = center.uniswapV2FactoryAddress();
        MockUniswapV2Factory uniswapFactory = MockUniswapV2Factory(
            uniswapFactoryAddr
        );
        MockUniswapV2Pair wrongPair = MockUniswapV2Pair(
            uniswapFactory.createPair(address(token1), address(token2))
        );

        vm.expectRevert(ILpFactoryErrors.InvalidJoinTokenPair.selector);
        factory.createExtension(
            address(token),
            address(wrongPair),
            GOV_RATIO_MULTIPLIER,
            MIN_GOV_RATIO
        );
    }

    // ============================================
    // View Function Tests (LP-specific)
    // ============================================

    function test_ImmutableVariables_GovRatioMultiplier() public view {
        assertEq(extension.GOV_RATIO_MULTIPLIER(), GOV_RATIO_MULTIPLIER);
        assertEq(extension.JOIN_TOKEN_ADDRESS(), address(joinToken));
        assertEq(extension.WAITING_BLOCKS(), 1);
    }

    // ============================================
    // RewardInfoByAccount Tests
    // ============================================

    function test_RewardInfoByAccount_BeforeRoundFinished() public {
        vm.prank(user1);
        extension.join(100e18, new string[](0));

        uint256 currentRound = verify.currentRound();

        // Before round is finished, mintReward should be 0
        (uint256 mintReward, uint256 burnReward, bool claimed) = extension
            .rewardByAccount(currentRound, user1);

        assertEq(mintReward, 0);
        assertEq(burnReward, 0);
        assertFalse(claimed);
    }

    function test_RewardInfoByAccount_AfterRoundFinished() public {
        vm.prank(user1);
        extension.join(100e18, new string[](0));

        // Advance to next round
        uint256 round = verify.currentRound();
        verify.setCurrentRound(round + 1);

        // Set action reward for the round
        uint256 totalReward = 1000e18;
        mint.setActionReward(address(token), round, ACTION_ID, totalReward);

        (uint256 mintReward, uint256 burnReward, bool claimed) = extension
            .rewardByAccount(round, user1);

        // User1 has 100% of LP (totalJoined = 100e18)
        // tokenRatio = 100e18 * 1e18 / 100e18 = 1e18
        // govRatio = 100e18 * 1e18 * 2 / 1000e18 = 2e17
        // score = min(1e18, 2e17) = 2e17
        // mintReward = 1000e18 * 2e17 / 1e18 = 200e18
        // theoreticalReward = 1000e18 * 1e18 / 1e18 = 1000e18
        // burnReward = 1000e18 - 200e18 = 800e18
        assertEq(mintReward, 200e18, "mintReward should be 200e18");
        assertEq(burnReward, 800e18, "burnReward should be 800e18");
        assertFalse(claimed);
    }

    function test_RewardInfoByAccount_MultipleUsers() public {
        vm.prank(user1);
        extension.join(100e18, new string[](0));
        vm.prank(user2);
        extension.join(200e18, new string[](0));

        // Advance to next round
        uint256 round = verify.currentRound();
        verify.setCurrentRound(round + 1);

        // Set action reward
        uint256 totalReward = 1000e18;
        mint.setActionReward(address(token), round, ACTION_ID, totalReward);

        // User1: tokenRatio = 100e18 * 1e18 / 300e18 = 333333333333333333, govRatio = 2e17, score = 2e17
        // User2: tokenRatio = 200e18 * 1e18 / 300e18 = 666666666666666666, govRatio = 4e17, score = 4e17

        (uint256 mintReward1, uint256 burnReward1, bool claimed1) = extension
            .rewardByAccount(round, user1);
        (uint256 mintReward2, uint256 burnReward2, bool claimed2) = extension
            .rewardByAccount(round, user2);

        // User1: mintReward = 1000e18 * 2e17 / 1e18 = 200e18
        //        theoreticalReward = 1000e18 * 333333333333333333 / 1e18 = 333333333333333333000
        //        burnReward = 333333333333333333000 - 200e18 = 133333333333333333000
        assertEq(mintReward1, 200e18, "User1 mintReward");
        assertEq(burnReward1, 133333333333333333000, "User1 burnReward");
        assertFalse(claimed1);

        // User2: mintReward = 1000e18 * 4e17 / 1e18 = 400e18
        //        theoreticalReward = 1000e18 * 666666666666666666 / 1e18 = 666666666666666666000
        //        burnReward = 666666666666666666000 - 400e18 = 266666666666666666000
        assertEq(mintReward2, 400e18, "User2 mintReward");
        assertEq(burnReward2, 266666666666666666000, "User2 burnReward");
        assertFalse(claimed2);
    }

    function test_RewardInfoByAccount_AfterClaim() public {
        vm.prank(user1);
        extension.join(100e18, new string[](0));

        // Advance to next round
        uint256 round = verify.currentRound();
        verify.setCurrentRound(round + 1);

        // Set action reward
        uint256 totalReward = 1000e18;
        mint.setActionReward(address(token), round, ACTION_ID, totalReward);

        // Claim reward
        vm.prank(user1);
        extension.claimReward(round);

        // Check reward info after claim
        (uint256 mintReward, uint256 burnReward, bool claimed) = extension
            .rewardByAccount(round, user1);

        assertEq(mintReward, 200e18, "mintReward should be 200e18");
        assertEq(burnReward, 800e18, "burnReward should be 800e18");
        assertTrue(claimed, "Should be minted after claim");
    }

    function test_RewardInfoByAccount_NonJoinedUser() public {
        vm.prank(user1);
        extension.join(100e18, new string[](0));

        uint256 round = verify.currentRound();
        verify.setCurrentRound(round + 1);

        uint256 totalReward = 1000e18;
        mint.setActionReward(address(token), round, ACTION_ID, totalReward);

        // User3 didn't join
        (uint256 mintReward, uint256 burnReward, bool claimed) = extension
            .rewardByAccount(round, user3);

        assertEq(mintReward, 0, "Non-joined user mintReward should be 0");
        assertEq(burnReward, 0, "Non-joined user burnReward should be 0");
        assertFalse(claimed);
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
            GOV_RATIO_MULTIPLIER,
            MIN_GOV_RATIO
        );

        assertTrue(factory.exists(newExtension));
        assertEq(factory.extensionsCount(), 2);
    }

    function test_Factory_Extensions() public {
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
            GOV_RATIO_MULTIPLIER,
            MIN_GOV_RATIO
        );

        address[] memory exts = factory.extensions();
        assertEq(exts.length, 2);
        assertEq(exts[0], address(extension));
        assertEq(exts[1], extension2);
    }

    function test_Factory_ExtensionsAtIndex() public {
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
            GOV_RATIO_MULTIPLIER,
            MIN_GOV_RATIO
        );

        assertEq(factory.extensionsAtIndex(0), address(extension));
        assertEq(factory.extensionsAtIndex(1), extension2);
    }

    function test_Factory_ExtensionParams() public {
        vm.prank(user1);
        joinToken.approve(address(extension), type(uint256).max);
        vm.prank(user1);
        extension.join(10e18, new string[](0));

        assertEq(
            extension.TOKEN_ADDRESS(),
            address(token),
            "tokenAddr mismatch"
        );
        assertEq(
            extension.JOIN_TOKEN_ADDRESS(),
            address(joinToken),
            "joinTokenAddr mismatch"
        );
        assertEq(extension.WAITING_BLOCKS(), 1, "WAITING_BLOCKS mismatch");
        assertEq(
            extension.GOV_RATIO_MULTIPLIER(),
            GOV_RATIO_MULTIPLIER,
            "govRatioMult mismatch"
        );
        assertEq(
            extension.MIN_GOV_RATIO(),
            MIN_GOV_RATIO,
            "minGovRatioVal mismatch"
        );
        assertEq(extension.actionId(), ACTION_ID, "actionId mismatch");
    }

    function test_Factory_Center() public view {
        assertEq(factory.CENTER_ADDRESS(), address(center));
    }

    function test_Factory_RevertIfInvalidJoinTokenAddress() public {
        vm.expectRevert(ITokenJoinErrors.InvalidJoinTokenAddress.selector);
        factory.createExtension(
            address(token),
            address(0),
            GOV_RATIO_MULTIPLIER,
            MIN_GOV_RATIO
        );
    }

    // ============================================
    // Min Gov Ratio Tests (LP-specific)
    // ============================================

    function test_Join_RevertIfInsufficientGovRatio() public {
        address poorUser = address(0x999);
        joinToken.mint(poorUser, 1000e18);
        vm.prank(poorUser);
        joinToken.approve(address(extension), type(uint256).max);

        // total=1000e18, 99e18 gives 9.9% < 10% = MIN_GOV_RATIO
        stake.setValidGovVotes(address(token), poorUser, 99e18);

        vm.prank(poorUser);
        vm.expectRevert(ILpErrors.InsufficientGovRatio.selector);
        extension.join(100e18, new string[](0));
    }

    function test_Join_RevertIfZeroTotalGovVotes() public {
        address newUser = address(0xa);
        joinToken.mint(newUser, 1000e18);
        vm.prank(newUser);
        joinToken.approve(address(extension), type(uint256).max);

        stake.setGovVotesNum(address(token), 0);
        stake.setValidGovVotes(address(token), newUser, 100e18);

        vm.prank(newUser);
        vm.expectRevert(ILpErrors.ZeroTotalGovVotes.selector);
        extension.join(100e18, new string[](0));

        stake.setGovVotesNum(address(token), 1000e18);
    }

    function test_Join_SucceedWithExactMinGovRatio() public {
        address minUser = address(0x888);
        joinToken.mint(minUser, 1000e18);
        vm.prank(minUser);
        joinToken.approve(address(extension), type(uint256).max);

        // total=1000e18, 100e18 gives 10% = MIN_GOV_RATIO
        stake.setValidGovVotes(address(token), minUser, 100e18);

        vm.prank(minUser);
        extension.join(100e18, new string[](0));

        (uint256 joinedRound, uint256 amount, , ) = extension.joinInfo(minUser);
        assertEq(joinedRound, join.currentRound());
        assertEq(amount, 100e18);
    }

    function test_Join_SucceedWithMoreThanMinGovRatio() public {
        address richUser = address(0x777);
        joinToken.mint(richUser, 1000e18);
        vm.prank(richUser);
        joinToken.approve(address(extension), type(uint256).max);

        stake.setValidGovVotes(address(token), richUser, 1000e18);

        vm.prank(richUser);
        extension.join(100e18, new string[](0));

        (, uint256 amount, , ) = extension.joinInfo(richUser);
        assertEq(amount, 100e18);
    }

    function test_ImmutableVariables_MinGovRatio() public view {
        assertEq(extension.MIN_GOV_RATIO(), MIN_GOV_RATIO);
    }

    // ============================================
    // BurnRewardIfNeeded Tests
    // ============================================

    function test_BurnRewardIfNeeded_NoParticipants_BurnAllReward() public {
        // Ensure extension is initialized (actionId is set)
        token.mint(address(extension), 1e18);
        extension.initializeIfNeeded();

        // Setup: no one joins in round 0
        uint256 round = verify.currentRound();

        // Advance to next round to make round 0 finished
        verify.setCurrentRound(round + 1);

        // Set action reward for round 0
        uint256 totalReward = 1000e18;
        mint.setActionReward(address(token), round, ACTION_ID, totalReward);

        // Get initial balances
        uint256 initialSupply = token.totalSupply();
        uint256 initialExtensionBalance = token.balanceOf(address(extension));

        // Call burnRewardIfNeeded - this will call _prepareRewardIfNeeded which calls mintActionReward
        // But MockMint doesn't actually mint, so we need to manually mint tokens to extension
        // The burnRewardIfNeeded will prepare the reward first, then calculate burn amount
        // Since no one participated, it should burn all reward
        // But extension needs to have the tokens to burn
        token.mint(address(extension), totalReward);

        // Call burnRewardIfNeeded - should burn all reward since no one participated
        extension.burnRewardIfNeeded(round);

        // Verify token supply decreased by totalReward
        assertEq(
            token.totalSupply(),
            initialSupply,
            "Token supply should decrease by totalReward (minted then burned)"
        );

        // Verify extension balance decreased by totalReward
        assertEq(
            token.balanceOf(address(extension)),
            initialExtensionBalance,
            "Extension balance should decrease by totalReward"
        );

        // Verify burnInfo
        (uint256 burnAmount, bool burned) = extension.burnInfo(round);
        assertEq(
            burnAmount,
            totalReward,
            "burnAmount should equal totalReward"
        );
        assertTrue(burned, "Should be marked as burned");
    }

    function test_BurnRewardIfNeeded_WithParticipants_NoBurn() public {
        // Setup: user1 joins in round 0
        vm.prank(user1);
        extension.join(100e18, new string[](0));

        uint256 round = verify.currentRound();

        // Advance to next round to make round 0 finished
        verify.setCurrentRound(round + 1);

        // Set action reward for round 0
        uint256 totalReward = 1000e18;
        mint.setActionReward(address(token), round, ACTION_ID, totalReward);

        // Ensure extension has enough tokens
        token.mint(address(extension), totalReward);

        // Get initial token supply
        uint256 initialSupply = token.totalSupply();

        // Call burnRewardIfNeeded - should not burn since someone participated
        extension.burnRewardIfNeeded(round);

        // Verify token supply unchanged (burning is handled by participants during claim)
        assertEq(
            token.totalSupply(),
            initialSupply,
            "Token supply should not change"
        );

        // Verify burnInfo
        // Note: Once burnRewardIfNeeded is called, _burned[round] is set to true
        // even if burnAmount is 0, so burned will be true
        (uint256 burnAmount, bool burned) = extension.burnInfo(round);
        assertEq(burnAmount, 0, "burnAmount should be 0");
        assertTrue(
            burned,
            "Should be marked as burned after burnRewardIfNeeded is called"
        );
    }

    function test_BurnRewardIfNeeded_WithParticipants_ThenClaim_BurnByParticipant()
        public
    {
        // Setup: user1 joins in round 0
        vm.prank(user1);
        extension.join(100e18, new string[](0));

        uint256 round = verify.currentRound();

        // Advance to next round to make round 0 finished
        verify.setCurrentRound(round + 1);

        // Set action reward for round 0
        uint256 totalReward = 1000e18;
        mint.setActionReward(address(token), round, ACTION_ID, totalReward);

        // Ensure extension has enough tokens
        token.mint(address(extension), totalReward);

        // Get initial token supply
        uint256 initialSupply = token.totalSupply();

        // Call burnRewardIfNeeded - should not burn
        extension.burnRewardIfNeeded(round);
        assertEq(
            token.totalSupply(),
            initialSupply,
            "No burn from burnRewardIfNeeded"
        );

        // User1 claims reward - this should burn their portion
        vm.prank(user1);
        extension.claimReward(round);

        // Verify token supply decreased (burnReward was burned during claim)
        // User1: tokenRatio = 1e18, govRatio = 2e17, score = 2e17
        // mintReward = 1000e18 * 2e17 / 1e18 = 200e18
        // theoreticalReward = 1000e18 * 1e18 / 1e18 = 1000e18
        // burnReward = 1000e18 - 200e18 = 800e18
        uint256 expectedBurn = 800e18;
        assertEq(
            token.totalSupply(),
            initialSupply - expectedBurn,
            "Token supply should decrease by burnReward"
        );
    }

    function test_BurnRewardIfNeeded_ZeroReward_NoBurn() public {
        uint256 round = verify.currentRound();

        // Advance to next round
        verify.setCurrentRound(round + 1);

        // Set zero action reward
        mint.setActionReward(address(token), round, ACTION_ID, 0);

        uint256 initialSupply = token.totalSupply();

        // Call burnRewardIfNeeded - should not burn anything
        extension.burnRewardIfNeeded(round);

        // Verify token supply unchanged
        assertEq(
            token.totalSupply(),
            initialSupply,
            "Token supply should not change"
        );

        // Verify burnInfo
        // Note: Once burnRewardIfNeeded is called, _burned[round] is set to true
        // even if burnAmount is 0, so burned will be true
        (uint256 burnAmount, bool burned) = extension.burnInfo(round);
        assertEq(burnAmount, 0, "burnAmount should be 0");
        assertTrue(
            burned,
            "Should be marked as burned after burnRewardIfNeeded is called"
        );
    }

    function test_BurnRewardIfNeeded_Idempotency() public {
        // Ensure extension is initialized (actionId is set)
        token.mint(address(extension), 1e18);
        extension.initializeIfNeeded();

        uint256 round = verify.currentRound();

        // Advance to next round
        verify.setCurrentRound(round + 1);

        uint256 totalReward = 1000e18;
        mint.setActionReward(address(token), round, ACTION_ID, totalReward);

        // Mint tokens to extension for burning
        token.mint(address(extension), totalReward);

        uint256 initialSupply = token.totalSupply();

        // First call
        extension.burnRewardIfNeeded(round);
        uint256 supplyAfterFirst = token.totalSupply();

        // Second call - should be idempotent (won't burn again)
        extension.burnRewardIfNeeded(round);
        uint256 supplyAfterSecond = token.totalSupply();

        // Verify both calls burned the same amount (or second call did nothing)
        assertEq(
            supplyAfterFirst,
            supplyAfterSecond,
            "Second call should not burn again"
        );
        assertEq(
            initialSupply - supplyAfterFirst,
            totalReward,
            "Should burn totalReward only once"
        );
    }

    function test_BurnRewardIfNeeded_RevertIfRoundNotFinished() public {
        uint256 currentRound = verify.currentRound();

        // Try to burn reward for current round (not finished yet)
        vm.expectRevert();
        extension.burnRewardIfNeeded(currentRound);
    }

    function test_BurnInfo_NoParticipants_ReturnsTotalReward() public {
        // Ensure extension is initialized (actionId is set)
        token.mint(address(extension), 1e18);
        extension.initializeIfNeeded();

        uint256 round = verify.currentRound();

        // Advance to next round
        verify.setCurrentRound(round + 1);

        uint256 totalReward = 1000e18;
        mint.setActionReward(address(token), round, ACTION_ID, totalReward);

        // Before burning - burnInfo should calculate based on _calculateBurnAmount
        // Since no one participated, it should return totalReward
        (uint256 burnAmount, bool burned) = extension.burnInfo(round);
        assertEq(
            burnAmount,
            totalReward,
            "burnAmount should equal totalReward"
        );
        assertFalse(burned, "Should not be burned yet");

        // After burning
        token.mint(address(extension), totalReward);
        extension.burnRewardIfNeeded(round);

        (burnAmount, burned) = extension.burnInfo(round);
        assertEq(
            burnAmount,
            totalReward,
            "burnAmount should equal totalReward"
        );
        assertTrue(burned, "Should be burned");
    }

    function test_BurnInfo_WithParticipants_ReturnsZero() public {
        // Setup: user1 joins
        vm.prank(user1);
        extension.join(100e18, new string[](0));

        uint256 round = verify.currentRound();

        // Advance to next round
        verify.setCurrentRound(round + 1);

        uint256 totalReward = 1000e18;
        mint.setActionReward(address(token), round, ACTION_ID, totalReward);

        // burnInfo should return 0 since someone participated
        (uint256 burnAmount, bool burned) = extension.burnInfo(round);
        assertEq(burnAmount, 0, "burnAmount should be 0");
        assertFalse(burned, "Should not be burned");
    }

    function test_BurnInfo_CurrentRound_ReturnsZero() public view {
        uint256 currentRound = verify.currentRound();

        (uint256 burnAmount, bool burned) = extension.burnInfo(currentRound);
        assertEq(burnAmount, 0, "burnAmount should be 0 for current round");
        assertFalse(burned, "Should not be burned for current round");
    }
}
