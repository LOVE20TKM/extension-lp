// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {Test} from "forge-std/Test.sol";
import {
    DeployContractsForTestIntegration
} from "./DeployContractsForTestIntegration.s.sol";
import {
    TestBaseNoDeployContractsForTest,
    FlowUserParams
} from "./TestBaseNoDeployContractsForTest.sol";
import {ExtensionCenter} from "@extension/src/ExtensionCenter.sol";
import {ExtensionLpFactory} from "../src/ExtensionLpFactory.sol";
import {ExtensionLp} from "../src/ExtensionLp.sol";
import {ILp} from "../src/interface/ILp.sol";
import {
    IExtensionFactory
} from "@extension/src/interface/IExtensionFactory.sol";
import {ILOVE20Token} from "@core/interfaces/ILOVE20Token.sol";
import {ILOVE20SLToken} from "@core/interfaces/ILOVE20SLToken.sol";
import {
    IUniswapV2Pair
} from "@core/uniswap-v2-core/interfaces/IUniswapV2Pair.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILOVE20Launch} from "@core/interfaces/ILOVE20Launch.sol";
import {ILOVE20Stake} from "@core/interfaces/ILOVE20Stake.sol";
import {ILOVE20Submit, ActionBody} from "@core/interfaces/ILOVE20Submit.sol";
import {ILOVE20Vote} from "@core/interfaces/ILOVE20Vote.sol";
import {ILOVE20Join} from "@core/interfaces/ILOVE20Join.sol";
import {ILOVE20Verify} from "@core/interfaces/ILOVE20Verify.sol";
import {ILOVE20Mint} from "@core/interfaces/ILOVE20Mint.sol";
import {
    IUniswapV2Factory
} from "@core/uniswap-v2-core/interfaces/IUniswapV2Factory.sol";
import {ILOVE20Submit} from "@core/interfaces/ILOVE20Submit.sol";
import {IMintable} from "@extension/lib/core/test/TestERC20.sol";
import {IETH20} from "@extension/lib/core/src/WETH/IETH20.sol";
import {
    SECOND_HALF_MIN_BLOCKS,
    FIRST_PARENT_TOKEN_FUNDRAISING_GOAL
} from "@extension/lib/core/test/Constant.sol";

contract TestExtensionLpHelper is TestBaseNoDeployContractsForTest {
    DeployContractsForTestIntegration public contractsIntegration;
    ExtensionCenter public extensionCenter;
    ExtensionLpFactory public extensionFactory;
    mapping(address => ExtensionLp) public extensionsByToken;

    FlowUserParams public bob;
    FlowUserParams public alice;

    uint256 public constant DEFAULT_GOV_RATIO_MULTIPLIER = 2;
    uint256 public constant DEFAULT_MIN_GOV_VOTES = 1e18;

    constructor() {
        // Parent constructor will call _setUp() which triggers DeployContractsForTest
        // But we override by setting up our own contracts after
        _setUpIntegration();
        _testContractsDeployedIntegration();
        // Deploy ExtensionCenter with real LOVE20 contracts
        extensionCenter = new ExtensionCenter(
            contractsIntegration.uniswapV2FactoryAddress(),
            contractsIntegration.launchAddress(),
            contractsIntegration.stakeAddress(),
            contractsIntegration.submitAddress(),
            contractsIntegration.voteAddress(),
            contractsIntegration.joinAddress(),
            contractsIntegration.verifyAddress(),
            contractsIntegration.mintAddress(),
            contractsIntegration.randomAddress()
        );

        // Deploy ExtensionLpFactory
        extensionFactory = new ExtensionLpFactory(address(extensionCenter));
    }

    function _setUpIntegration() internal {
        // Deploy contracts using integration test deployment (with precompiled bytecode)
        contractsIntegration = new DeployContractsForTestIntegration();
        contractsIntegration.run();

        // Update TestBaseCore state to use our deployment
        uniswapV2Factory = IUniswapV2Factory(
            contractsIntegration.uniswapV2FactoryAddress()
        );
        rootParentTokenAddress = contractsIntegration.rootParentTokenAddress();
        launchContract = ILOVE20Launch(contractsIntegration.launchAddress());
        stakeContract = ILOVE20Stake(contractsIntegration.stakeAddress());
        submitContract = ILOVE20Submit(contractsIntegration.submitAddress());
        voteContract = ILOVE20Vote(contractsIntegration.voteAddress());
        joinContract = ILOVE20Join(contractsIntegration.joinAddress());
        verifyContract = ILOVE20Verify(contractsIntegration.verifyAddress());
        mintContract = ILOVE20Mint(contractsIntegration.mintAddress());

        firstTokenAddress = launchContract.tokensAtIndex(0);

        // Set contracts variable to avoid null reference (but it won't be used)
        // This is needed because TestBaseCore expects a contracts variable
        // We'll use contractsIntegration instead
    }

    function _testContractsDeployedIntegration() internal view {
        assertNotEq(
            contractsIntegration.uniswapV2FactoryAddress(),
            address(0),
            "Uniswap V2 factory address should be deployed"
        );
        assertNotEq(
            contractsIntegration.rootParentTokenAddress(),
            address(0),
            "Root parent token address should be deployed"
        );
        assertNotEq(
            contractsIntegration.launchAddress(),
            address(0),
            "Launch address should be deployed"
        );
        assertNotEq(
            contractsIntegration.submitAddress(),
            address(0),
            "Submit address should be deployed"
        );
        assertNotEq(
            contractsIntegration.stakeAddress(),
            address(0),
            "Stake address should be deployed"
        );
        assertNotEq(
            contractsIntegration.voteAddress(),
            address(0),
            "Vote address should be deployed"
        );
        assertNotEq(
            contractsIntegration.joinAddress(),
            address(0),
            "Join address should be deployed"
        );
        assertNotEq(
            contractsIntegration.randomAddress(),
            address(0),
            "Random address should be deployed"
        );
        assertNotEq(
            contractsIntegration.verifyAddress(),
            address(0),
            "Verify address should be deployed"
        );
        assertNotEq(
            contractsIntegration.mintAddress(),
            address(0),
            "Mint address should be deployed"
        );
        assertNotEq(
            firstTokenAddress,
            address(0),
            "First token address should be deployed"
        );
    }

    function createExtension(
        address tokenAddress,
        uint256 govRatioMultiplier,
        uint256 minGovVotes
    ) public returns (ExtensionLp) {
        // Get real UniswapV2Pair from SL Token
        address slTokenAddress = ILOVE20Token(tokenAddress).slAddress();
        address pairAddress = ILOVE20SLToken(slTokenAddress).uniswapV2Pair();

        // Mint token for factory registration
        IERC20(tokenAddress).approve(address(extensionFactory), 1e18);
        forceMint(tokenAddress, address(this), 1e18);

        // Create extension
        address extensionAddress = extensionFactory.createExtension(
            tokenAddress,
            pairAddress,
            govRatioMultiplier,
            minGovVotes
        );

        ExtensionLp extension = ExtensionLp(extensionAddress);
        extensionsByToken[tokenAddress] = extension;

        return extension;
    }

    function createExtensionWithDefaults(
        address tokenAddress
    ) public returns (ExtensionLp) {
        return
            createExtension(
                tokenAddress,
                DEFAULT_GOV_RATIO_MULTIPLIER,
                DEFAULT_MIN_GOV_VOTES
            );
    }

    function getPairAddress(
        address tokenAddress
    ) public view returns (address) {
        address slTokenAddress = ILOVE20Token(tokenAddress).slAddress();
        return ILOVE20SLToken(slTokenAddress).uniswapV2Pair();
    }

    function getLpToken(
        address tokenAddress
    ) public view returns (IUniswapV2Pair) {
        return IUniswapV2Pair(getPairAddress(tokenAddress));
    }

    function extension_join(
        FlowUserParams memory p,
        ExtensionLp extension,
        uint256 lpAmount
    ) public {
        IUniswapV2Pair lpToken = getLpToken(p.tokenAddress);

        // Get LP tokens for user (directly from Uniswap pair)
        uint256 lpBalance = lpToken.balanceOf(p.userAddress);
        if (lpBalance < lpAmount) {
            // Add liquidity directly to Uniswap pair to get LP tokens
            // Add extra to account for rounding and MINIMUM_LIQUIDITY
            _addLiquidityToPair(p, (lpAmount - lpBalance) * 2);
            lpBalance = lpToken.balanceOf(p.userAddress);
            // Use actual balance if it's less than requested (due to rounding)
            if (lpBalance < lpAmount) {
                lpAmount = lpBalance;
            }
        }

        // Approve extension to spend LP tokens
        vm.startPrank(p.userAddress);
        IERC20(address(lpToken)).approve(address(extension), lpAmount);
        extension.join(lpAmount, new string[](0));
        vm.stopPrank();
    }

    function _addLiquidityToPair(
        FlowUserParams memory p,
        uint256 desiredLpAmount
    ) internal {
        IUniswapV2Pair pair = getLpToken(p.tokenAddress);
        ILOVE20Token token = ILOVE20Token(p.tokenAddress);
        address parentTokenAddr = token.parentTokenAddress();

        // Calculate amounts needed
        (
            uint256 tokenAmount,
            uint256 parentTokenAmount
        ) = _calculateLiquidityAmounts(pair, p.tokenAddress, desiredLpAmount);

        // Ensure user has enough tokens
        _ensureUserHasTokens(
            p.userAddress,
            p.tokenAddress,
            parentTokenAddr,
            tokenAmount,
            parentTokenAmount
        );

        // Transfer tokens to pair and mint LP tokens
        vm.startPrank(p.userAddress);
        IERC20(p.tokenAddress).approve(address(pair), tokenAmount);
        IERC20(parentTokenAddr).approve(address(pair), parentTokenAmount);
        IERC20(p.tokenAddress).transfer(address(pair), tokenAmount);
        IERC20(parentTokenAddr).transfer(address(pair), parentTokenAmount);
        pair.mint(p.userAddress);
        vm.stopPrank();
    }

    function _calculateLiquidityAmounts(
        IUniswapV2Pair pair,
        address tokenAddress,
        uint256 desiredLpAmount
    ) internal view returns (uint256 tokenAmount, uint256 parentTokenAmount) {
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        address token0 = pair.token0();
        bool isToken0 = (token0 == tokenAddress);
        uint256 tokenReserve = isToken0 ? reserve0 : reserve1;
        uint256 parentTokenReserve = isToken0 ? reserve1 : reserve0;
        uint256 totalSupply = pair.totalSupply();

        if (totalSupply == 0) {
            uint256 targetLp = desiredLpAmount + 1000; // MINIMUM_LIQUIDITY
            return (targetLp, targetLp);
        } else {
            tokenAmount = (desiredLpAmount * tokenReserve) / totalSupply;
            parentTokenAmount =
                (desiredLpAmount * parentTokenReserve) /
                totalSupply;
        }
    }

    function _ensureUserHasTokens(
        address user,
        address tokenAddress,
        address parentTokenAddr,
        uint256 tokenAmount,
        uint256 parentTokenAmount
    ) internal {
        uint256 userTokenBal = IERC20(tokenAddress).balanceOf(user);
        if (userTokenBal < tokenAmount) {
            forceMint(tokenAddress, user, tokenAmount - userTokenBal);
        }
        uint256 userParentBal = IERC20(parentTokenAddr).balanceOf(user);
        if (userParentBal < parentTokenAmount) {
            uint256 needed = parentTokenAmount - userParentBal;
            if (parentTokenAddr == rootParentTokenAddress) {
                vm.deal(user, needed);
                vm.startPrank(user);
                IETH20(rootParentTokenAddress).deposit{value: needed}();
                vm.stopPrank();
            } else {
                IMintable(parentTokenAddr).mint(user, needed);
            }
        }
    }

    // Helper function to ensure user has minimum tokens before staking
    function ensureUserHasMinimumTokensForStaking(
        FlowUserParams memory p
    ) public {
        ILOVE20Token token = ILOVE20Token(p.tokenAddress);
        address parentTokenAddr = token.parentTokenAddress();
        uint256 tokenBalance = token.balanceOf(p.userAddress);
        uint256 parentTokenBalance = IERC20(parentTokenAddr).balanceOf(
            p.userAddress
        );

        // Calculate expected amounts
        uint256 tokenAmountForLp = (tokenBalance *
            p.stake.tokenAmountForLpPercent) / 100;
        uint256 parentTokenAmountForLp = (parentTokenBalance *
            p.stake.parentTokenAmountForLpPercent) / 100;

        // Ensure minimum amounts to avoid StakeAmountMustBeSet error
        uint256 minParentTokenAmount = 1e15; // Minimum 0.001 parent token
        if (parentTokenAmountForLp == 0 && tokenAmountForLp > 0) {
            // If parent token amount is 0 but token amount is not, ensure minimum parent token
            _ensureUserHasTokens(
                p.userAddress,
                p.tokenAddress,
                parentTokenAddr,
                0,
                minParentTokenAmount
            );
        } else if (parentTokenAmountForLp > 0) {
            // Ensure user has enough tokens for the calculated amounts
            _ensureUserHasTokens(
                p.userAddress,
                p.tokenAddress,
                parentTokenAddr,
                tokenAmountForLp,
                parentTokenAmountForLp
            );
        }
    }

    function extension_claimReward(
        FlowUserParams memory p,
        ExtensionLp extension,
        uint256 round
    ) public {
        vm.startPrank(p.userAddress);
        extension.claimReward(round);
        vm.stopPrank();
    }

    function extension_withdraw(
        FlowUserParams memory p,
        ExtensionLp extension
    ) public {
        vm.startPrank(p.userAddress);
        extension.exit();
        vm.stopPrank();
    }

    function mint_action_reward_for_extension(
        FlowUserParams memory p,
        address extensionAddress
    ) public {
        ILOVE20Token token = ILOVE20Token(p.tokenAddress);
        uint256 latestRoundCanMint = verifyContract.currentRound() - 1;

        // For extension, the reward is minted to extension address, not user address
        // So we need to calculate expected reward based on extension address
        uint256 expectedReward = 0;
        if (
            mintContract.isActionIdWithReward(
                p.tokenAddress,
                latestRoundCanMint,
                p.actionId
            )
        ) {
            if (
                mintContract.actionRewardMintedByAccount(
                    p.tokenAddress,
                    latestRoundCanMint,
                    p.actionId,
                    extensionAddress
                ) == 0
            ) {
                uint256 totalActionReward = mintContract.actionReward(
                    p.tokenAddress,
                    latestRoundCanMint
                );
                uint256 scores = verifyContract.scoreByActionIdByAccount(
                    p.tokenAddress,
                    latestRoundCanMint,
                    p.actionId,
                    extensionAddress
                );

                if (scores > 0) {
                    uint256 totalScoreWithReward = verifyContract
                        .scoreWithReward(p.tokenAddress, latestRoundCanMint);
                    uint256 totalAbstentionScoreWithReward = verifyContract
                        .abstentionScoreWithReward(
                            p.tokenAddress,
                            latestRoundCanMint
                        );
                    expectedReward =
                        (totalActionReward * scores) /
                        (totalScoreWithReward - totalAbstentionScoreWithReward);
                }
            }
        }

        // store before values (for extension address)
        uint256 extensionTokenBalanceBefore = token.balanceOf(extensionAddress);
        uint256 totalSupplyBefore = token.totalSupply();

        // mint as the extension address
        vm.startPrank(extensionAddress); // Prank as extension
        uint256 actualReward = mintContract.mintActionReward(
            p.tokenAddress,
            latestRoundCanMint,
            p.actionId
        );
        vm.stopPrank();

        // check
        assertEq(actualReward, expectedReward, "action reward amount mismatch");
        assertEq(
            token.balanceOf(extensionAddress),
            extensionTokenBalanceBefore + actualReward,
            "extension token balance incorrect after minting"
        );
        assertEq(
            token.totalSupply(),
            totalSupplyBefore + actualReward,
            "total token supply incorrect after minting"
        );
    }

    /// @notice Submit a new action with extension address as whiteListAddress
    function submit_new_action_with_extension(
        FlowUserParams memory p,
        address extensionAddress
    ) public returns (uint256 actionId) {
        ActionBody memory actionBody;
        actionBody.minStake = p.submit.minStake;
        actionBody.maxRandomAccounts = p.submit.maxRandomAccounts;
        actionBody.whiteListAddress = extensionAddress;
        actionBody.title = p.submit.title;
        actionBody.verificationRule = p.submit.verificationRule;
        actionBody.verificationKeys = p.submit.verificationKeys;
        actionBody.verificationInfoGuides = p.submit.verificationInfoGuides;

        // Get extension creator to ensure action author matches extension creator
        address extensionCreator = IExtensionFactory(extensionFactory)
            .extensionCreator(extensionAddress);

        // Ensure extension creator has stake to submit
        // Create a temporary FlowUserParams for extension creator
        FlowUserParams memory creatorParams;
        creatorParams.userAddress = extensionCreator;
        creatorParams.tokenAddress = p.tokenAddress;
        creatorParams.stake.tokenAmountForLpPercent = 50;
        creatorParams.stake.parentTokenAmountForLpPercent = 50;
        creatorParams.stake.tokenAmountPercent = 50;
        creatorParams.stake.promisedWaitingPhases = 4;

        // Check if extension creator can already submit, if not, set up stake with large amount
        if (!submitContract.canSubmit(p.tokenAddress, extensionCreator)) {
            address parentAddr = ILOVE20Token(p.tokenAddress)
                .parentTokenAddress();
            uint256 totalV = stakeContract.govVotesNum(p.tokenAddress);
            uint256 minPer = submitContract.SUBMIT_MIN_PER_THOUSAND();
            // Use a very large multiplier (50x) to ensure we exceed the threshold
            // This accounts for complex gov votes calculation and ensures we have enough
            uint256 needed = totalV > 0 ? (totalV * minPer * 50) / 1000 : 1e18;
            // Start with a large base amount to ensure we have enough votes
            uint256 amt = needed > 100000e18
                ? (needed > 5000000e18 ? 5000000e18 : needed)
                : 100000e18;

            // Keep staking until canSubmit is true (with maximum iterations)
            for (
                uint256 iter = 0;
                iter < 8 &&
                    !submitContract.canSubmit(p.tokenAddress, extensionCreator);
                iter++
            ) {
                // Ensure creator has enough tokens for this iteration
                uint256 neededToken = amt * 2;
                uint256 neededParent = amt;
                if (
                    IERC20(p.tokenAddress).balanceOf(extensionCreator) <
                    neededToken
                ) {
                    forceMint(p.tokenAddress, extensionCreator, neededToken);
                }
                if (
                    IERC20(parentAddr).balanceOf(extensionCreator) <
                    neededParent
                ) {
                    if (parentAddr == rootParentTokenAddress) {
                        vm.deal(extensionCreator, neededParent);
                        vm.startPrank(extensionCreator);
                        IETH20(rootParentTokenAddress).deposit{
                            value: neededParent
                        }();
                        vm.stopPrank();
                    } else {
                        IMintable(parentAddr).mint(
                            extensionCreator,
                            neededParent
                        );
                    }
                }

                // Stake liquidity and token
                vm.startPrank(extensionCreator);
                IERC20(p.tokenAddress).approve(address(stakeContract), amt);
                IERC20(parentAddr).approve(address(stakeContract), amt);
                stakeContract.stakeLiquidity(
                    p.tokenAddress,
                    amt,
                    amt,
                    creatorParams.stake.promisedWaitingPhases,
                    extensionCreator
                );
                IERC20(p.tokenAddress).approve(address(stakeContract), amt);
                stakeContract.stakeToken(
                    p.tokenAddress,
                    amt,
                    creatorParams.stake.promisedWaitingPhases,
                    extensionCreator
                );
                vm.stopPrank();

                // Double the amount for next iteration
                amt = amt * 2;
            }
        }

        // Submit action as extension creator
        vm.startPrank(extensionCreator);
        actionId = submitContract.submitNewAction(p.tokenAddress, actionBody);
        vm.stopPrank();

        return actionId;
    }

    // Copy from TestFlowHelper
    function createUser(
        string memory userName,
        address tokenAddress,
        uint256 mintAmountOfParentToken
    ) public returns (FlowUserParams memory) {
        address parentTokenAddress = ILOVE20Token(tokenAddress)
            .parentTokenAddress();
        address userAddress = makeAddr(userName);

        FlowUserParams memory user;
        // user
        user.userName = userName;
        user.userAddress = userAddress;
        // default var
        user.tokenAddress = tokenAddress;
        user.actionId = 0;
        // launch
        user.launch.contributeParentTokenAmountPercent = 50;
        user.launch.contributeParentTokenAmount = 0;
        user.launch.contributeToAddress = userAddress;
        // stake
        user.stake.tokenAmountForLpPercent = 50;
        user.stake.parentTokenAmountForLpPercent = 50;
        user.stake.tokenAmountPercent = 50;
        user.stake.promisedWaitingPhases = 4;
        // submit
        user.submit.minStake = 100;
        user.submit.maxRandomAccounts = 3;
        user.submit.whiteListAddress = address(0);
        user.submit.title = "default title";
        user.submit.verificationRule = "default verificationRule";
        user.submit.verificationKeys = new string[](1);
        user.submit.verificationKeys[0] = "default";
        user.submit.verificationInfoGuides = new string[](1);
        user.submit.verificationInfoGuides[0] = "default verificationInfoGuide";
        // vote
        user.vote.votePercent = 100;
        // join
        user.join.tokenAmountPercent = 50;
        user.join.additionalTokenAmountPercent = 50;
        user.join.verificationInfos = new string[](1);
        user.join.verificationInfos[0] = "default verificationInfo";
        user.join.updateVerificationInfos = new string[](1);
        user.join.updateVerificationInfos[0] = "updated verificationInfo";
        user.join.rounds = 4;
        // verify
        user.verify.scorePercent = 50;

        if (parentTokenAddress == rootParentTokenAddress) {
            vm.deal(user.userAddress, mintAmountOfParentToken);
            vm.startPrank(user.userAddress);
            IETH20(rootParentTokenAddress).deposit{
                value: mintAmountOfParentToken
            }();
            vm.stopPrank();
        } else {
            forceMint(
                parentTokenAddress,
                user.userAddress,
                mintAmountOfParentToken
            );
        }

        return user;
    }

    function getUserBob() public view returns (FlowUserParams memory) {
        return bob;
    }

    function getUserAlice() public view returns (FlowUserParams memory) {
        return alice;
    }

    function jump_second_half_min() public {
        vm.roll(block.number + SECOND_HALF_MIN_BLOCKS);
    }

    function finish_launch()
        public
        returns (FlowUserParams memory user1, FlowUserParams memory user2)
    {
        bob = createUser(
            "bob",
            firstTokenAddress,
            FIRST_PARENT_TOKEN_FUNDRAISING_GOAL
        );
        alice = createUser(
            "alice",
            firstTokenAddress,
            FIRST_PARENT_TOKEN_FUNDRAISING_GOAL
        );

        launch_contribute(bob);

        jump_second_half_min(); // make sure the second half min is reached
        launch_contribute(alice);

        launch_skip_claim_delay();

        launch_claim(bob);
        launch_claim(alice);

        return (bob, alice);
    }
}
