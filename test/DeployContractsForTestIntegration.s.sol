// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {Script} from "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";
import {DeployLOVE20} from "@extension/lib/core/script/DeployLOVE20.s.sol";
import {PrecompiledDeployer} from "./artifacts/PrecompiledDeployer.sol";
import "@extension/lib/core/test/Constant.sol";

contract DeployContractsForTestIntegration is Script, Test, PrecompiledDeployer {
    DeployLOVE20 public script;

    address public uniswapV2FactoryAddress;
    address public rootParentTokenAddress;

    address public launchAddress;
    address public stakeAddress;
    address public submitAddress;
    address public voteAddress;
    address public joinAddress;
    address public randomAddress;
    address public verifyAddress;
    address public mintAddress;

    function run() external {
        // Deploy WETH using precompiled bytecode
        vm.startBroadcast();
        rootParentTokenAddress = deployETH20("Wrapped ETH", "WETH");
        
        // Deploy UniswapV2Factory using precompiled bytecode
        uniswapV2FactoryAddress = deployUniswapV2Factory(address(0));
        vm.stopBroadcast();

        // Deploy LOVE20
        script = new DeployLOVE20();
        script.setHideLogs(true);
        script.setEnableUpdateParamsFile(false);
        script.run(
            DeployLOVE20.DeployParams({
                rootParentTokenAddress: rootParentTokenAddress,
                uniswapV2FactoryAddress: uniswapV2FactoryAddress,
                tokenSymbolLength: TOKEN_SYMBOL_LENGTH,
                firstTokenSymbol: FIRST_TOKEN_SYMBOL,
                firstParentTokenFundraisingGoal: FIRST_PARENT_TOKEN_FUNDRAISING_GOAL,
                parentTokenFundraisingGoal: PARENT_TOKEN_FUNDRAISING_GOAL,
                secondHalfMinBlocks: SECOND_HALF_MIN_BLOCKS,
                totalSupply: MAX_SUPPLY,
                launchAmount: LAUNCH_AMOUNT,
                withdrawWaitingBlocks: WITHDRAW_WAITING_BLOCKS,
                minGovRewardMintsToLaunch: MIN_GOV_REWARD_MINTS_TO_LAUNCH,
                phaseBlocks: PHASE_BLOCKS,
                maxWithdrawableToFeeRatio: MAX_WITHDRAWABLE_TO_FEE_RATIO,
                joinEndPhaseBlocks: JOIN_END_PHASE_BLOCKS,
                promisedWaitingPhasesMin: PROMISED_WAITING_PHASES_MIN,
                promisedWaitingPhasesMax: PROMISED_WAITING_PHASES_MAX,
                submitMinPerThousand: SUBMIT_MIN_PER_THOUSAND,
                maxVerificationKeyLength: MAX_VERIFICATION_KEY_LENGTH,
                randomSeedUpdateMinPerTenThousand: RANDOM_SEED_UPDATE_MIN_PER_TEN_THOUSAND,
                actionRewardMinVotePerThousand: ACTION_REWARD_MIN_VOTE_PER_THOUSAND,
                roundRewardGovPerThousand: ROUND_REWARD_GOV_PER_THOUSAND,
                roundRewardActionPerThousand: ROUND_REWARD_ACTION_PER_THOUSAND,
                maxGovBoostRewardMultiplier: MAX_GOV_BOOST_REWARD_MULTIPLIER
            })
        );

        rootParentTokenAddress = script.rootParentTokenAddress();
        uniswapV2FactoryAddress = script.uniswapV2FactoryAddress();
        launchAddress = script.launchAddress();
        stakeAddress = script.stakeAddress();
        submitAddress = script.submitAddress();
        voteAddress = script.voteAddress();
        joinAddress = script.joinAddress();
        randomAddress = script.randomAddress();
        verifyAddress = script.verifyAddress();
        mintAddress = script.mintAddress();
    }
}

