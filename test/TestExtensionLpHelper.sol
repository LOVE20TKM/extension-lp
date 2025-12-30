// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {Test} from "forge-std/Test.sol";
import {
    DeployContractsForTestIntegration
} from "./DeployContractsForTestIntegration.s.sol";
import {ExtensionCenter} from "@extension/src/ExtensionCenter.sol";
import {ExtensionFactoryLp} from "../src/ExtensionFactoryLp.sol";
import {ExtensionLp} from "../src/ExtensionLp.sol";
import {IExtensionLp} from "../src/interface/IExtensionLp.sol";
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
import {
    TestLaunchHelper
} from "@extension/lib/core/test/helper/TestLaunchHelper.sol";
import {
    TestStakeHelper
} from "@extension/lib/core/test/helper/TestStakeHelper.sol";
import {
    TestSubmitHelper
} from "@extension/lib/core/test/helper/TestSubmitHelper.sol";
import {
    TestVoteHelper
} from "@extension/lib/core/test/helper/TestVoteHelper.sol";
import {
    TestJoinHelper
} from "@extension/lib/core/test/helper/TestJoinHelper.sol";
import {
    TestVerifyHelper
} from "@extension/lib/core/test/helper/TestVerifyHelper.sol";
import {
    TestMintHelper
} from "@extension/lib/core/test/helper/TestMintHelper.sol";
import {
    TestBaseHelper,
    FlowUserParams
} from "@extension/lib/core/test/TestBaseHelper.sol";
import {TestFlowHelper} from "@extension/lib/core/test/TestFlowHelper.sol";

contract TestExtensionLpHelper is TestFlowHelper {
    DeployContractsForTestIntegration public contractsIntegration;
    ExtensionCenter public extensionCenter;
    ExtensionFactoryLp public extensionFactory;
    mapping(address => ExtensionLp) public extensionsByToken;

    uint256 public constant DEFAULT_WAITING_BLOCKS = 7;
    uint256 public constant DEFAULT_GOV_RATIO_MULTIPLIER = 2;
    uint256 public constant DEFAULT_MIN_GOV_VOTES = 1e18;

    constructor() {
        // Skip parent constructor initialization by calling our own setup
        // This prevents the parent constructor from calling DeployContractsForTest
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

        // Deploy ExtensionFactoryLp
        extensionFactory = new ExtensionFactoryLp(address(extensionCenter));
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
        uint256 waitingBlocks,
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
            waitingBlocks,
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
                DEFAULT_WAITING_BLOCKS,
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
            IMintable(parentTokenAddr).mint(
                user,
                parentTokenAmount - userParentBal
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

    // Override submit_new_action to skip canJoin check when whiteListAddress is extension address
    // This is needed because extensions use whiteListAddress to identify themselves,
    // but users join through extension, not directly through LOVE20Join
    // We can't override the parent function (it's not virtual), so we'll use a different approach:
    // Temporarily set whiteListAddress to address(0) for the check, then restore it
    function submit_new_action_with_extension(
        FlowUserParams memory p,
        address extensionAddress
    ) public returns (uint256 actionId) {
        // Save original whiteListAddress
        address originalWhiteListAddress = p.submit.whiteListAddress;

        // Temporarily set to extension address for submission
        p.submit.whiteListAddress = extensionAddress;

        // Call parent submit_new_action, but it will fail canJoin check
        // So we need to manually submit and skip the canJoin check
        _beforeValues["actionNum"] = submitContract.actionsCount(
            p.tokenAddress
        );
        _beforeValues["authorActionIdsLength"] = submitContract
            .authorActionIdsCount(p.tokenAddress, p.userAddress);
        _beforeValues["actionSubmitInfoLength"] = submitContract
            .actionSubmitsCount(p.tokenAddress, submitContract.currentRound());

        // submitNewAction
        ActionBody memory actionBody;
        actionBody.minStake = p.submit.minStake;
        actionBody.maxRandomAccounts = p.submit.maxRandomAccounts;
        actionBody.whiteListAddress = extensionAddress;
        actionBody.title = p.submit.title;
        actionBody.verificationRule = p.submit.verificationRule;
        actionBody.verificationKeys = p.submit.verificationKeys;
        actionBody.verificationInfoGuides = p.submit.verificationInfoGuides;

        vm.startPrank(p.userAddress);
        actionId = submitContract.submitNewAction(p.tokenAddress, actionBody);
        vm.stopPrank();

        // check (skip canJoin check since whiteListAddress is extension address)
        _check_submit_new_action_infos(p, actionId, actionBody);
        _check_submit_new_action_author(p, actionId);
        _check_submit_action_functions(p, actionId, actionBody);
        // Skip _check_submit_base which includes canJoin check

        // Restore original whiteListAddress
        p.submit.whiteListAddress = originalWhiteListAddress;

        return actionId;
    }
}
