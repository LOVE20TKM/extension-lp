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
    // govRatio Tests
    // ============================================

    /// @notice When not claimed, returns current gov ratio and claimed=false
    function test_GovRatio_NotClaimed_ReturnsCurrentGovRatioAndClaimedFalse()
        public
    {
        vm.prank(user1);
        extension.join(100e18, new string[](0));

        uint256 targetRound = verify.currentRound();
        verify.setCurrentRound(targetRound + 1);

        // setUp: govVotesNum(token)=1000e18, validGovVotes(token, user1)=100e18
        // Expected ratio = 100e18 * 1e18 / 1000e18 = 0.1e18
        uint256 govTotal = 1000e18;
        uint256 govValid = 100e18;
        uint256 expectedGovRatio = (govValid * 1e18) / govTotal;

        (uint256 ratio, bool claimed) = extension.govRatio(targetRound, user1);
        assertEq(ratio, expectedGovRatio, "govRatio should be current ratio");
        assertFalse(claimed, "claimed should be false");
    }

    /// @notice When claimed, returns stored gov ratio at claim time and claimed=true; later stake change does not change returned ratio
    function test_GovRatio_Claimed_ReturnsStoredGovRatioAndClaimedTrue()
        public
    {
        vm.prank(user1);
        extension.join(100e18, new string[](0));

        uint256 targetRound = verify.currentRound();
        verify.setCurrentRound(targetRound + 1);

        uint256 govTotalBefore = 1000e18;
        uint256 govValidBefore = 100e18;
        uint256 expectedStoredRatio = (govValidBefore * 1e18) / govTotalBefore;

        mint.setActionReward(address(token), targetRound, ACTION_ID, 1000e18);
        vm.prank(user1);
        extension.claimReward(targetRound);

        (uint256 ratioAfterClaim, bool claimedAfter) = extension.govRatio(
            targetRound,
            user1
        );
        assertEq(
            ratioAfterClaim,
            expectedStoredRatio,
            "govRatio after claim should be ratio at claim time"
        );
        assertTrue(claimedAfter, "claimed should be true");

        // Change stake so current ratio would differ; stored ratio must remain
        stake.setValidGovVotes(address(token), user1, 500e18);
        stake.setGovVotesNum(address(token), 1000e18);

        (uint256 ratioLater, bool claimedLater) = extension.govRatio(
            targetRound,
            user1
        );
        assertEq(
            ratioLater,
            expectedStoredRatio,
            "govRatio should stay stored value after stake change"
        );
        assertTrue(claimedLater, "claimed should still be true");
    }

    /// @notice When govTotal is 0, returns govRatio=0 and claimed=false for unclaimed account
    function test_GovRatio_GovTotalZero_ReturnsZeroRatio() public {
        stake.setGovVotesNum(address(token), 0);
        stake.setValidGovVotes(address(token), user1, 100e18);

        (uint256 ratio, bool claimed) = extension.govRatio(0, user1);
        assertEq(ratio, 0, "govRatio should be 0 when govTotal is 0");
        assertFalse(claimed, "claimed should be false");
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

    // ============================================
    // Helper: Create Extension with Custom Params
    // ============================================

    function _createExtensionWithParams(
        uint256 govRatioMultiplier,
        uint256 minGovRatio,
        uint256 newActionId
    ) internal returns (ExtensionLp) {
        token.mint(address(this), 1e18);
        token.approve(address(factory), 1e18);
        ExtensionLp newExt = ExtensionLp(
            factory.createExtension(
                address(token),
                address(joinToken),
                govRatioMultiplier,
                minGovRatio
            )
        );

        submit.setActionInfo(address(token), newActionId, address(newExt));
        submit.setActionAuthor(address(token), newActionId, address(this));
        vote.setVotedActionIds(
            address(token),
            join.currentRound(),
            newActionId
        );
        token.mint(address(newExt), 10000e18);
        return newExt;
    }

    // ============================================
    // GOV_RATIO_MULTIPLIER == 0 Reward Tests
    // ============================================

    function test_RewardCalculation_GovRatioMultiplierZero_FullBlockRatio()
        public
    {
        uint256 newActionId = 2;
        ExtensionLp extZero = _createExtensionWithParams(0, 0, newActionId);

        vm.prank(user1);
        joinToken.approve(address(extZero), type(uint256).max);
        vm.prank(user1);
        extZero.join(100e18, new string[](0));

        uint256 round = verify.currentRound();
        verify.setCurrentRound(round + 1);

        uint256 totalReward = 1000e18;
        mint.setActionReward(address(token), round, newActionId, totalReward);

        (uint256 mintReward, uint256 burnReward, bool claimed) = extZero
            .rewardByAccount(round, user1);

        // User1 has 100% LP, joined at start of round -> blockRatio = 100%
        // GOV_RATIO_MULTIPLIER == 0 -> only LP ratio and block ratio matter
        // mintReward = theoreticalReward * blockRatio / PRECISION = 1000e18
        assertEq(
            mintReward,
            1000e18,
            "Full block ratio mint should equal total reward"
        );
        assertEq(burnReward, 0, "Full block ratio burn should be 0");
        assertFalse(claimed);
    }

    function test_RewardCalculation_GovRatioMultiplierZero_PartialBlockRatio()
        public
    {
        uint256 newActionId = 2;
        ExtensionLp extZero = _createExtensionWithParams(0, 0, newActionId);

        // Join at block 150 (mid round 1: blocks 100-199)
        vm.roll(150);
        vm.prank(user1);
        joinToken.approve(address(extZero), type(uint256).max);
        vm.prank(user1);
        extZero.join(100e18, new string[](0));

        uint256 round = verify.currentRound();
        verify.setCurrentRound(round + 1);

        uint256 totalReward = 1000e18;
        mint.setActionReward(address(token), round, newActionId, totalReward);

        (uint256 mintReward, uint256 burnReward, bool claimed) = extZero
            .rewardByAccount(round, user1);

        // roundEndBlock = 0 + (1+1)*100 - 1 = 199
        // blocksInRound = 199 - 150 + 1 = 50
        // blockRatio = 50 * 1e18 / 100 = 5e17 (50%)
        // mintReward = 1000e18 * 5e17 / 1e18 = 500e18
        // burnReward = 1000e18 - 500e18 = 500e18
        assertEq(mintReward, 500e18, "Partial block ratio mint");
        assertEq(burnReward, 500e18, "Partial block ratio burn");
        assertFalse(claimed);
    }

    // ============================================
    // totalGovVotes == 0 Reward Tests
    // ============================================

    function test_RewardCalculation_TotalGovVotesZero() public {
        // user1 joins with existing gov ratio (100e18/1000e18 = 10% >= MIN_GOV_RATIO)
        vm.prank(user1);
        extension.join(100e18, new string[](0));

        // Set totalGovVotes to 0 AFTER joining
        stake.setGovVotesNum(address(token), 0);

        uint256 round = verify.currentRound();
        verify.setCurrentRound(round + 1);

        uint256 totalReward = 1000e18;
        mint.setActionReward(address(token), round, ACTION_ID, totalReward);

        (uint256 mintReward, uint256 burnReward, bool claimed) = extension
            .rewardByAccount(round, user1);

        // totalGovVotes == 0 and GOV_RATIO_MULTIPLIER != 0
        // -> return (0, theoreticalReward) = (0, 1000e18)
        assertEq(mintReward, 0, "Mint should be 0 when totalGovVotes is 0");
        assertEq(
            burnReward,
            1000e18,
            "Burn should equal full theoretical reward"
        );
        assertFalse(claimed);
    }

    // ============================================
    // effectiveRatio == lpRatio (Zero Burn) Tests
    // ============================================

    function test_RewardCalculation_GovRatioLargerThanLpRatio_ZeroBurn()
        public
    {
        // Give user1 ALL gov votes so govVotesRatio >= lpRatio
        stake.setValidGovVotes(address(token), user1, 1000e18);

        vm.prank(user1);
        extension.join(100e18, new string[](0));

        uint256 round = verify.currentRound();
        verify.setCurrentRound(round + 1);

        uint256 totalReward = 1000e18;
        mint.setActionReward(address(token), round, ACTION_ID, totalReward);

        (uint256 mintReward, uint256 burnReward, bool claimed) = extension
            .rewardByAccount(round, user1);

        // lpRatio = 100e18 * 1e18 / 100e18 = 1e18 (100%)
        // govVotesRatio = 1000e18 * 1e18 * 2 / 1000e18 = 2e18 (200%)
        // effectiveRatio = min(1e18, 2e18) = 1e18
        // blockRatio = 1e18 (joined at start of round)
        // mintReward = 1000e18 * 1e18 / 1e18 = 1000e18
        // burnReward = 1000e18 - 1000e18 = 0
        assertEq(mintReward, 1000e18, "All reward should be minted");
        assertEq(burnReward, 0, "No burn when gov ratio >= lp ratio");
        assertFalse(claimed);
    }

    // ============================================
    // claimRewards (Batch) Tests
    // ============================================

    function test_ClaimRewards_BatchClaim() public {
        vm.prank(user1);
        extension.join(100e18, new string[](0));

        uint256 round1 = verify.currentRound(); // 1

        // Set rewards for round 1 and round 2
        mint.setActionReward(address(token), round1, ACTION_ID, 1000e18);
        mint.setActionReward(
            address(token),
            round1 + 1,
            ACTION_ID,
            500e18
        );

        // Advance verify to make both rounds claimable
        verify.setCurrentRound(round1 + 2);

        // Pre-calculate expected rewards
        // Round 1: lpRatio=1e18, govVotesRatio=2e17, effectiveRatio=2e17
        //   blockRatio=1e18 (joined at start of round)
        //   mintReward = 1000e18 * 2e17 / 1e18 = 200e18
        //   burnReward = 1000e18 - 200e18 = 800e18
        uint256 expectedMint1 = 200e18;
        uint256 expectedBurn1 = 800e18;
        // Round 2: LP continues (joinedBlock==0 for round 2), blockRatio=1e18
        //   mintReward = 500e18 * 2e17 / 1e18 = 100e18
        //   burnReward = 500e18 - 100e18 = 400e18
        uint256 expectedMint2 = 100e18;
        uint256 expectedBurn2 = 400e18;

        uint256[] memory rounds = new uint256[](2);
        rounds[0] = round1;
        rounds[1] = round1 + 1;

        uint256 balanceBefore = token.balanceOf(user1);

        vm.prank(user1);
        (
            uint256[] memory claimedRounds,
            uint256[] memory mintRewards,
            uint256[] memory burnRewards
        ) = extension.claimRewards(rounds);

        assertEq(claimedRounds.length, 2, "Should claim 2 rounds");
        assertEq(claimedRounds[0], round1);
        assertEq(claimedRounds[1], round1 + 1);
        assertEq(mintRewards[0], expectedMint1, "Round 1 mint");
        assertEq(mintRewards[1], expectedMint2, "Round 2 mint");
        assertEq(burnRewards[0], expectedBurn1, "Round 1 burn");
        assertEq(burnRewards[1], expectedBurn2, "Round 2 burn");

        assertEq(
            token.balanceOf(user1) - balanceBefore,
            expectedMint1 + expectedMint2,
            "Total mint transfer"
        );

        (, , bool claimed1) = extension.rewardByAccount(round1, user1);
        (, , bool claimed2) = extension.rewardByAccount(round1 + 1, user1);
        assertTrue(claimed1, "Round 1 claimed");
        assertTrue(claimed2, "Round 2 claimed");
    }

    function test_ClaimRewards_SkipsAlreadyClaimed() public {
        vm.prank(user1);
        extension.join(100e18, new string[](0));

        uint256 round1 = verify.currentRound();
        uint256 round2 = round1 + 1;

        mint.setActionReward(address(token), round1, ACTION_ID, 1000e18);
        mint.setActionReward(address(token), round2, ACTION_ID, 500e18);
        verify.setCurrentRound(round1 + 2);

        // Claim round 1 individually
        vm.prank(user1);
        extension.claimReward(round1);

        // Batch claim both - round 1 should be skipped
        uint256[] memory rounds = new uint256[](2);
        rounds[0] = round1;
        rounds[1] = round2;

        vm.prank(user1);
        (
            uint256[] memory claimedRounds,
            uint256[] memory mintRewards,
            uint256[] memory burnRewards
        ) = extension.claimRewards(rounds);

        // Only round 2 should be claimed
        assertEq(claimedRounds.length, 1, "Should only claim round 2");
        assertEq(claimedRounds[0], round2);
        assertEq(mintRewards[0], 100e18, "Round 2 mint");
        assertEq(burnRewards[0], 400e18, "Round 2 burn");
    }

    // ============================================
    // lastJoinedBlockByAccountByJoinedRound Tests
    // ============================================

    function test_LastJoinedBlockByAccountByJoinedRound_FirstJoin() public {
        // user1 joins at block 100 (from setUp vm.roll(100))
        vm.prank(user1);
        extension.join(50e18, new string[](0));

        uint256 round = join.currentRound();
        assertEq(
            extension.lastJoinedBlockByAccountByJoinedRound(user1, round),
            100,
            "Should record block 100 for first join"
        );
    }

    function test_LastJoinedBlockByAccountByJoinedRound_UpdatedOnSameRound()
        public
    {
        vm.prank(user1);
        extension.join(50e18, new string[](0));

        vm.roll(110);
        vm.prank(user1);
        extension.join(50e18, new string[](0));

        uint256 round = join.currentRound();
        assertEq(
            extension.lastJoinedBlockByAccountByJoinedRound(user1, round),
            110,
            "Should update to block 110 on second join"
        );
    }

    function test_LastJoinedBlockByAccountByJoinedRound_NotUpdatedAcrossRounds()
        public
    {
        // user1 joins in round 1 at block 100
        vm.prank(user1);
        extension.join(50e18, new string[](0));

        uint256 round1 = join.currentRound(); // 1

        // Advance to round 2
        join.setCurrentRound(2);
        vote.setVotedActionIds(address(token), 2, ACTION_ID);

        // Add more LP in round 2 (not first join, and currentRound != joinedRound)
        vm.roll(200);
        vm.prank(user1);
        extension.join(50e18, new string[](0));

        // Round 1 block should still be 100
        assertEq(
            extension.lastJoinedBlockByAccountByJoinedRound(user1, round1),
            100,
            "Round 1 join block should still be 100"
        );

        // Round 2 should be 0 (not updated since not first join and not joinedRound)
        assertEq(
            extension.lastJoinedBlockByAccountByJoinedRound(user1, 2),
            0,
            "Round 2 join block should be 0 (not updated)"
        );
    }
}
