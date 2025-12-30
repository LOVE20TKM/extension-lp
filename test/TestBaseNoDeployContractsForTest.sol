// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {Test, console, stdError} from "forge-std/Test.sol";
import {IMintable} from "@extension/lib/core/test/TestERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PHASE_BLOCKS} from "@extension/lib/core/test/Constant.sol";

import {
    IUniswapV2Factory
} from "@core/uniswap-v2-core/interfaces/IUniswapV2Factory.sol";
import {ILOVE20Token} from "@core/interfaces/ILOVE20Token.sol";
import {
    ILOVE20Launch,
    LaunchInfo,
    CLAIM_DELAY_BLOCKS
} from "@core/interfaces/ILOVE20Launch.sol";
import {
    ILOVE20Stake,
    AccountStakeStatus
} from "@core/interfaces/ILOVE20Stake.sol";
import {ILOVE20Submit, ActionBody} from "@core/interfaces/ILOVE20Submit.sol";
import {ILOVE20Vote} from "@core/interfaces/ILOVE20Vote.sol";
import {ILOVE20Join} from "@core/interfaces/ILOVE20Join.sol";
import {ILOVE20Verify} from "@core/interfaces/ILOVE20Verify.sol";
import {ILOVE20Mint} from "@core/interfaces/ILOVE20Mint.sol";
import {ILOVE20TokenFactory} from "@core/interfaces/ILOVE20TokenFactory.sol";
import {ILOVE20SLToken} from "@core/interfaces/ILOVE20SLToken.sol";
import {ILOVE20STToken} from "@core/interfaces/ILOVE20STToken.sol";
import {
    IUniswapV2Pair
} from "@core/uniswap-v2-core/interfaces/IUniswapV2Pair.sol";
import {
    IERC20Metadata
} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IETH20} from "@extension/lib/core/src/WETH/IETH20.sol";

// Import struct definitions from TestBaseCore
import {
    LaunchParams,
    StakeParams,
    SubmitParams,
    VoteParams,
    JoinParams,
    VerifyParams,
    FlowUserParams
} from "@extension/lib/core/test/helper/TestBaseCore.sol";

/// @title TestBaseNoDeployContractsForTest
/// @notice Base test contract that provides helper functions without using DeployContractsForTest
/// @dev This avoids the vm.getCode() issue with core library's Solidity 0.5.x contracts
abstract contract TestBaseNoDeployContractsForTest is Test {
    IUniswapV2Factory public uniswapV2Factory;
    address public rootParentTokenAddress;
    address public firstTokenAddress;
    ILOVE20Launch public launchContract;
    ILOVE20Stake public stakeContract;
    ILOVE20Submit public submitContract;
    ILOVE20Vote public voteContract;
    ILOVE20Join public joinContract;
    ILOVE20Verify public verifyContract;
    ILOVE20Mint public mintContract;

    mapping(string => uint256) internal _beforeValues;
    mapping(string => uint256) internal _expectedValues;

    // ============ Utility Functions ============

    function forceMint(
        address tokenAddress,
        address to,
        uint256 amount
    ) public {
        if (tokenAddress != rootParentTokenAddress) {
            vm.startPrank(ILOVE20Token(tokenAddress).minter());
            IMintable(tokenAddress).mint(to, amount);
            vm.stopPrank();
        } else {
            IMintable(tokenAddress).mint(to, amount);
        }
    }

    function burnForParentToken(FlowUserParams memory p) public {
        ILOVE20Token token = ILOVE20Token(p.tokenAddress);
        IERC20 parentToken = IERC20(token.parentTokenAddress());

        uint256 balance = IERC20(p.tokenAddress).balanceOf(p.userAddress);
        vm.startPrank(p.userAddress);
        ILOVE20Token(p.tokenAddress).burnForParentToken(balance);
        vm.stopPrank();
    }

    function next_phase() public {
        vm.roll(block.number + PHASE_BLOCKS);
    }

    function next_phases(uint256 num) public {
        vm.roll(block.number + num * PHASE_BLOCKS);
    }

    // ============ Launch Helper Functions ============

    function launch_contribute(FlowUserParams memory p) public {
        ILOVE20Token token = ILOVE20Token(p.tokenAddress);
        IERC20 parentToken = IERC20(token.parentTokenAddress());

        uint256 parentTokenAmount = p.launch.contributeParentTokenAmount > 0
            ? p.launch.contributeParentTokenAmount
            : (p.launch.contributeParentTokenAmountPercent *
                parentToken.balanceOf(p.userAddress)) / 100;

        vm.startPrank(p.userAddress);
        parentToken.approve(address(launchContract), parentTokenAmount);
        launchContract.contribute(
            p.tokenAddress,
            parentTokenAmount,
            p.launch.contributeToAddress
        );
        vm.stopPrank();
    }

    function launch_skip_claim_delay() public {
        vm.roll(block.number + CLAIM_DELAY_BLOCKS);
    }

    function launch_claim(FlowUserParams memory p) public {
        vm.startPrank(p.launch.contributeToAddress);
        launchContract.claim(p.tokenAddress);
        vm.stopPrank();
    }

    // ============ Stake Helper Functions ============

    function stake_liquidity(FlowUserParams memory p) public {
        ILOVE20Token token = ILOVE20Token(p.tokenAddress);
        IERC20 parentToken = IERC20(token.parentTokenAddress());

        uint256 tokenBalance = token.balanceOf(p.userAddress);
        uint256 parentTokenBalance = parentToken.balanceOf(p.userAddress);
        uint256 tokenAmountForLp = (tokenBalance *
            p.stake.tokenAmountForLpPercent) / 100;
        uint256 parentTokenAmountForLp = (parentTokenBalance *
            p.stake.parentTokenAmountForLpPercent) / 100;

        vm.startPrank(p.userAddress);
        token.approve(address(stakeContract), tokenAmountForLp);
        parentToken.approve(address(stakeContract), parentTokenAmountForLp);
        stakeContract.stakeLiquidity(
            p.tokenAddress,
            tokenAmountForLp,
            parentTokenAmountForLp,
            p.stake.promisedWaitingPhases,
            p.userAddress
        );
        vm.stopPrank();
    }

    function stake_token(FlowUserParams memory p) public {
        ILOVE20Token token = ILOVE20Token(p.tokenAddress);
        uint256 tokenBalance = token.balanceOf(p.userAddress);
        uint256 tokenAmount = (tokenBalance * p.stake.tokenAmountPercent) / 100;

        vm.startPrank(p.userAddress);
        token.approve(address(stakeContract), tokenAmount);
        stakeContract.stakeToken(
            p.tokenAddress,
            tokenAmount,
            p.stake.promisedWaitingPhases,
            p.userAddress
        );
        vm.stopPrank();
    }

    function stake_unstake(FlowUserParams memory p) public {
        ILOVE20Token token = ILOVE20Token(p.tokenAddress);
        ILOVE20SLToken slToken = ILOVE20SLToken(token.slAddress());
        ILOVE20STToken stToken = ILOVE20STToken(token.stAddress());

        uint256 slAmount = slToken.balanceOf(p.userAddress);
        uint256 stAmount = stToken.balanceOf(p.userAddress);

        vm.startPrank(p.userAddress);
        slToken.approve(address(stakeContract), slAmount);
        stToken.approve(address(stakeContract), stAmount);
        stakeContract.unstake(p.tokenAddress);
        vm.stopPrank();
    }

    function stake_withdraw(FlowUserParams memory p) public {
        vm.startPrank(p.userAddress);
        stakeContract.withdraw(p.tokenAddress);
        vm.stopPrank();
    }

    // ============ Vote Helper Functions ============

    function vote(FlowUserParams memory p) public {
        uint256 govVotes = stakeContract
            .accountStakeStatus(p.tokenAddress, p.userAddress)
            .govVotes;
        uint256 voteNum = (govVotes * p.vote.votePercent) / 100;

        uint256[] memory actionIds = new uint256[](1);
        actionIds[0] = p.actionId;
        uint256[] memory votes = new uint256[](1);
        votes[0] = voteNum;

        vm.startPrank(p.userAddress);
        voteContract.vote(p.tokenAddress, actionIds, votes);
        vm.stopPrank();
    }

    // ============ Verify Helper Functions ============

    function verify(FlowUserParams memory p) public {
        // Get votes for this action
        uint256[] memory actionIds = new uint256[](1);
        actionIds[0] = p.actionId;
        uint256[] memory votes = voteContract.votesNumsByAccountByActionIds(
            p.tokenAddress,
            verifyContract.currentRound(),
            p.userAddress,
            actionIds
        );
        uint256 maxVotes = votes[0];

        // Get random accounts for this action
        address[] memory randomAccounts = joinContract.randomAccounts(
            p.tokenAddress,
            verifyContract.currentRound(),
            p.actionId
        );
        uint256 randomAccountsNum = randomAccounts.length;

        if (randomAccountsNum == 0) return;

        // Calculate scores
        uint256[] memory scores = new uint256[](randomAccountsNum);
        uint256 abstentionScore = maxVotes;
        uint256 scoreByAccount = (maxVotes * p.verify.scorePercent) /
            randomAccountsNum /
            100;
        for (uint256 i = 0; i < randomAccountsNum; i++) {
            scores[i] = scoreByAccount;
            abstentionScore -= scores[i];
        }

        vm.startPrank(p.userAddress);
        verifyContract.verify(
            p.tokenAddress,
            p.actionId,
            abstentionScore,
            scores
        );
        vm.stopPrank();
    }

    // ============ Mint Helper Functions ============

    function mint_gov_reward(FlowUserParams memory p) public {
        uint256 latestRoundCanMint = verifyContract.currentRound() - 1;
        vm.startPrank(p.userAddress);
        mintContract.mintGovReward(p.tokenAddress, latestRoundCanMint);
        vm.stopPrank();
    }
}
