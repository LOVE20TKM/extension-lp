// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {Test, console} from "forge-std/Test.sol";
import {LOVE20ExtensionLp} from "../src/LOVE20ExtensionLp.sol";
import {LOVE20ExtensionFactoryLp} from "../src/LOVE20ExtensionFactoryLp.sol";
import {ILOVE20ExtensionLp} from "../src/interface/ILOVE20ExtensionLp.sol";
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
 * @dev This test suite focuses on LP-specific features:
 *      - LP token validation
 *      - LP to token conversion (joinedValue)
 *      - govRatioMultiplier in reward calculation
 *      - rewardInfoByAccount with mint/burn rewards
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

        // Setup submit permissions (mock only)
        submit.setCanSubmit(address(token), address(this), true);

        // Set action info whiteListAddress to extension address
        submit.setActionInfo(address(token), ACTION_ID, address(extension));

        // Set vote mock for auto-initialization
        vote.setVotedActionIds(address(token), join.currentRound(), ACTION_ID);

        // Setup users with join tokens
        joinToken.mint(user1, 100e18);
        joinToken.mint(user2, 200e18);
        joinToken.mint(user3, 300e18);

        // Set initial total supply for joinToken (for ratio calculations)
        joinToken.mint(address(0x1), 1000e18);

        // Set Pair reserves for LP to token conversion
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
        MockERC20 invalidStakeToken = new MockERC20();

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
        MockERC20 token1 = new MockERC20();
        MockERC20 token2 = new MockERC20();
        address uniswapFactoryAddr = center.uniswapV2FactoryAddress();
        MockUniswapV2Factory uniswapFactory = MockUniswapV2Factory(
            uniswapFactoryAddr
        );
        MockUniswapV2Pair wrongPair = MockUniswapV2Pair(
            uniswapFactory.createPair(address(token1), address(token2))
        );

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
        assertEq(extension.govRatioMultiplier(), GOV_RATIO_MULTIPLIER);
        assertEq(extension.joinTokenAddress(), address(joinToken));
        assertEq(extension.waitingBlocks(), WAITING_BLOCKS);
    }

    function test_IsJoinedValueCalculated() public view {
        assertTrue(extension.isJoinedValueCalculated());
    }

    // ============================================
    // LP to Token Conversion Tests (joinedValue)
    // ============================================

    function test_JoinedValue() public {
        vm.prank(user1);
        extension.join(100e18, new string[](0));

        IUniswapV2Pair pair = IUniswapV2Pair(address(joinToken));
        uint256 totalLpSupply = pair.totalSupply();
        uint256 joindLpAmount = 100e18;

        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        address pairToken0 = pair.token0();
        uint256 tokenReserve = (pairToken0 == address(token))
            ? uint256(reserve0)
            : uint256(reserve1);

        uint256 expectedTokenAmount = (joindLpAmount * tokenReserve) /
            totalLpSupply;
        assertEq(extension.joinedValue(), expectedTokenAmount);
    }

    function test_JoinedValueByAccount() public {
        vm.prank(user1);
        extension.join(50e18, new string[](0));

        vm.prank(user2);
        extension.join(100e18, new string[](0));

        IUniswapV2Pair pair = IUniswapV2Pair(address(joinToken));
        uint256 totalLpSupply = pair.totalSupply();

        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        address pairToken0 = pair.token0();
        uint256 tokenReserve = (pairToken0 == address(token))
            ? uint256(reserve0)
            : uint256(reserve1);

        uint256 expectedTokenAmount1 = (50e18 * tokenReserve) / totalLpSupply;
        uint256 expectedTokenAmount2 = (100e18 * tokenReserve) / totalLpSupply;
        assertEq(extension.joinedValueByAccount(user1), expectedTokenAmount1);
        assertEq(extension.joinedValueByAccount(user2), expectedTokenAmount2);
    }

    function test_JoinedValue_ZeroWhenNoStakes() public view {
        assertEq(extension.joinedValue(), 0);
    }

    // ============================================
    // RewardInfoByAccount Tests
    // ============================================

    function test_RewardInfoByAccount_BeforeRoundFinished() public {
        vm.prank(user1);
        extension.join(100e18, new string[](0));

        uint256 currentRound = verify.currentRound();

        // Before round is finished, mintReward should be 0
        (uint256 mintReward, uint256 burnReward, bool isMinted) = extension
            .rewardInfoByAccount(currentRound, user1);

        assertEq(mintReward, 0);
        assertEq(burnReward, 0);
        assertFalse(isMinted);
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

        (uint256 mintReward, uint256 burnReward, bool isMinted) = extension
            .rewardInfoByAccount(round, user1);

        // User1 has 100% of LP (totalJoined = 100e18)
        // tokenRatio = 100e18 * 1000 / 100e18 = 1000
        // govRatio = 100e18 * 1000 * 2 / 1000e18 = 200
        // score = min(1000, 200) = 200
        // mintReward = 1000e18 * 200 / 1000 = 200e18
        // theoreticalReward = 1000e18 * 1000 / 1000 = 1000e18
        // burnReward = 1000e18 - 200e18 = 800e18
        assertEq(mintReward, 200e18, "mintReward should be 200e18");
        assertEq(burnReward, 800e18, "burnReward should be 800e18");
        assertFalse(isMinted);
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

        // User1: tokenRatio = 100e18 * 1000 / 300e18 = 333, govRatio = 200, score = 200
        // User2: tokenRatio = 200e18 * 1000 / 300e18 = 666, govRatio = 400, score = 400

        (uint256 mintReward1, uint256 burnReward1, bool isMinted1) = extension
            .rewardInfoByAccount(round, user1);
        (uint256 mintReward2, uint256 burnReward2, bool isMinted2) = extension
            .rewardInfoByAccount(round, user2);

        // User1: mintReward = 1000e18 * 200 / 1000 = 200e18
        //        theoreticalReward = 1000e18 * 333 / 1000 = 333e18
        //        burnReward = 333e18 - 200e18 = 133e18
        assertEq(mintReward1, 200e18, "User1 mintReward");
        assertEq(burnReward1, 133e18, "User1 burnReward");
        assertFalse(isMinted1);

        // User2: mintReward = 1000e18 * 400 / 1000 = 400e18
        //        theoreticalReward = 1000e18 * 666 / 1000 = 666e18
        //        burnReward = 666e18 - 400e18 = 266e18
        assertEq(mintReward2, 400e18, "User2 mintReward");
        assertEq(burnReward2, 266e18, "User2 burnReward");
        assertFalse(isMinted2);
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
        (uint256 mintReward, uint256 burnReward, bool isMinted) = extension
            .rewardInfoByAccount(round, user1);

        assertEq(mintReward, 200e18, "mintReward should be 200e18");
        assertEq(burnReward, 800e18, "burnReward should be 800e18");
        assertTrue(isMinted, "Should be minted after claim");
    }

    function test_RewardInfoByAccount_NonJoinedUser() public {
        vm.prank(user1);
        extension.join(100e18, new string[](0));

        uint256 round = verify.currentRound();
        verify.setCurrentRound(round + 1);

        uint256 totalReward = 1000e18;
        mint.setActionReward(address(token), round, ACTION_ID, totalReward);

        // User3 didn't join
        (uint256 mintReward, uint256 burnReward, bool isMinted) = extension
            .rewardInfoByAccount(round, user3);

        assertEq(mintReward, 0, "Non-joined user mintReward should be 0");
        assertEq(burnReward, 0, "Non-joined user burnReward should be 0");
        assertFalse(isMinted);
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

        assertEq(
            extension.tokenAddress(),
            address(token),
            "tokenAddr mismatch"
        );
        assertEq(extension.actionId(), ACTION_ID, "actionId mismatch");
    }

    function test_Factory_ExtensionParams_NonExistent() public view {
        (
            address tokenAddr,
            address joinTokenAddr,
            uint256 waitingBlocks,
            uint256 govRatioMult,
            uint256 minGovVotesVal,
            uint256 lpRatioPrecision
        ) = factory.extensionParams(address(0x999));

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
        vm.prank(user1);
        vm.expectRevert(ILOVE20ExtensionLp.InsufficientLpRatio.selector);
        extension.join(1e18, new string[](0));
    }

    function test_Join_SucceedWithSufficientLpRatio() public {
        uint256 minRequired = (joinToken.totalSupply() +
            LP_RATIO_PRECISION -
            1) / LP_RATIO_PRECISION;
        vm.prank(user1);
        extension.join(minRequired, new string[](0));

        assertEq(extension.totalJoinedAmount(), minRequired);
    }

    function test_Join_NoRestrictionWhenLpRatioPrecisionIsZero() public {
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

        submit.setActionInfo(address(token), ACTION_ID + 100, newExtensionAddr);
        vote.setVotedActionIds(
            address(token),
            join.currentRound(),
            ACTION_ID + 100
        );
        token.mint(newExtensionAddr, 1e18);

        LOVE20ExtensionLp newExtension = LOVE20ExtensionLp(newExtensionAddr);

        vm.prank(user1);
        joinToken.approve(address(newExtension), type(uint256).max);

        vm.prank(user1);
        newExtension.join(1, new string[](0));

        assertEq(newExtension.totalJoinedAmount(), 1);
    }

    function test_ImmutableVariables_LpRatioPrecision() public view {
        assertEq(extension.lpRatioPrecision(), LP_RATIO_PRECISION);
    }

    // ============================================
    // Min Gov Votes Tests (LP-specific)
    // ============================================

    function test_Join_RevertIfInsufficientGovVotes() public {
        address poorUser = address(0x999);
        joinToken.mint(poorUser, 1000e18);
        vm.prank(poorUser);
        joinToken.approve(address(extension), type(uint256).max);

        stake.setValidGovVotes(address(token), poorUser, MIN_GOV_VOTES - 1);

        vm.prank(poorUser);
        vm.expectRevert(ILOVE20ExtensionLp.InsufficientGovVotes.selector);
        extension.join(100e18, new string[](0));
    }

    function test_Join_SucceedWithExactMinGovVotes() public {
        address minUser = address(0x888);
        joinToken.mint(minUser, 1000e18);
        vm.prank(minUser);
        joinToken.approve(address(extension), type(uint256).max);

        stake.setValidGovVotes(address(token), minUser, MIN_GOV_VOTES);

        vm.prank(minUser);
        extension.join(100e18, new string[](0));

        (uint256 joinedRound, uint256 amount, , ) = extension.joinInfo(minUser);
        assertEq(joinedRound, join.currentRound());
        assertEq(amount, 100e18);
    }

    function test_Join_SucceedWithMoreThanMinGovVotes() public {
        address richUser = address(0x777);
        joinToken.mint(richUser, 1000e18);
        vm.prank(richUser);
        joinToken.approve(address(extension), type(uint256).max);

        stake.setValidGovVotes(address(token), richUser, MIN_GOV_VOTES * 10);

        vm.prank(richUser);
        extension.join(100e18, new string[](0));

        (, uint256 amount, , ) = extension.joinInfo(richUser);
        assertEq(amount, 100e18);
    }

    function test_ImmutableVariables_MinGovVotes() public view {
        assertEq(extension.minGovVotes(), MIN_GOV_VOTES);
    }
}
