// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {ILp} from "./interface/ILp.sol";
import {
    ExtensionBaseRewardTokenJoin
} from "@extension/src/ExtensionBaseRewardTokenJoin.sol";
import {RoundHistoryUint256} from "@extension/src/lib/RoundHistoryUint256.sol";
import {ILOVE20Token} from "@core/interfaces/ILOVE20Token.sol";
import {ILOVE20Stake} from "@core/interfaces/ILOVE20Stake.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract ExtensionLp is ExtensionBaseRewardTokenJoin, ILp {
    using RoundHistoryUint256 for RoundHistoryUint256.History;
    using SafeERC20 for IERC20;

    uint256 public constant DEFAULT_WAITING_BLOCKS = 1;
    uint256 internal constant PRECISION = 1e18;

    uint256 public immutable GOV_RATIO_MULTIPLIER;
    uint256 public immutable MIN_GOV_VOTES;

    ILOVE20Stake internal immutable _stake;

    /// @dev round => account => burnReward (recorded at claim time)
    mapping(uint256 => mapping(address => uint256))
        internal _burnedRewardByAccount;

    /// @dev account => joinedRound => last joined block in that round (0 means not joined in that round)
    mapping(address => mapping(uint256 => uint256))
        internal _lastJoinedBlockByAccountByJoinedRound;

    constructor(
        address factory_,
        address tokenAddress_,
        address joinTokenAddress_,
        uint256 govRatioMultiplier_,
        uint256 minGovVotes_
    )
        ExtensionBaseRewardTokenJoin(
            factory_,
            tokenAddress_,
            joinTokenAddress_,
            DEFAULT_WAITING_BLOCKS
        )
    {
        GOV_RATIO_MULTIPLIER = govRatioMultiplier_;
        MIN_GOV_VOTES = minGovVotes_;
        _stake = ILOVE20Stake(_center.stakeAddress());
    }

    function join(
        uint256 amount,
        string[] memory verificationInfos
    ) public virtual override(ExtensionBaseRewardTokenJoin) {
        bool isFirstJoin = _lastJoinedBlockByAccount[msg.sender] == 0;

        if (isFirstJoin) {
            uint256 userGovVotes = _stake.validGovVotes(
                TOKEN_ADDRESS,
                msg.sender
            );
            if (userGovVotes < MIN_GOV_VOTES) {
                revert InsufficientGovVotes();
            }
        }

        uint256 currentRound = _join.currentRound();
        if (isFirstJoin || currentRound == _joinedRoundByAccount[msg.sender]) {
            _lastJoinedBlockByAccountByJoinedRound[msg.sender][
                currentRound
            ] = block.number;
        }

        super.join(amount, verificationInfos);
    }

    function _calculateRewardBreakdown(
        uint256 round,
        address account
    ) internal view returns (uint256 mintReward, uint256 burnReward) {
        if (round >= _verify.currentRound()) {
            return (0, 0);
        }

        // prepare
        uint256 totalActionReward = reward(round);

        if (totalActionReward == 0) {
            return (0, 0);
        }

        uint256 joinedAmount = _joinedAmountByAccountHistory[account].value(
            round
        );
        uint256 totalJoined = _joinedAmountHistory.value(round);

        if (totalJoined == 0 || joinedAmount == 0) {
            return (0, 0);
        }

        // calculate reward
        uint256 lpRatio = (joinedAmount * PRECISION) / totalJoined;
        uint256 theoreticalReward = (totalActionReward * lpRatio) / PRECISION;

        // calculate block ratio only if joined in this round
        uint256 blockRatio = PRECISION;
        uint256 joinedBlock = _lastJoinedBlockByAccountByJoinedRound[account][
            round
        ];
        if (joinedBlock != 0) {
            uint256 phaseBlocks = _join.phaseBlocks();
            uint256 roundEndBlock = _join.originBlocks() +
                (round + 1) *
                phaseBlocks -
                1;
            uint256 blocksInRound = roundEndBlock - joinedBlock + 1;
            blockRatio = (blocksInRound * PRECISION) / phaseBlocks;
        }

        if (GOV_RATIO_MULTIPLIER == 0) {
            uint256 adjustedTheoreticalReward = (theoreticalReward *
                blockRatio) / PRECISION;
            return (
                adjustedTheoreticalReward,
                theoreticalReward - adjustedTheoreticalReward
            );
        }

        // calculate burn reward
        uint256 totalGovVotes = _stake.govVotesNum(TOKEN_ADDRESS);
        if (totalGovVotes == 0) {
            return (0, theoreticalReward);
        }
        uint256 govVotes = _stake.validGovVotes(TOKEN_ADDRESS, account);
        uint256 govVotesRatio = (govVotes * PRECISION * GOV_RATIO_MULTIPLIER) /
            totalGovVotes;

        uint256 effectiveRatio = lpRatio < govVotesRatio
            ? lpRatio
            : govVotesRatio;
        uint256 adjustedEffectiveRatio = blockRatio == PRECISION
            ? effectiveRatio
            : (effectiveRatio * blockRatio) / PRECISION;

        mintReward = (totalActionReward * adjustedEffectiveRatio) / PRECISION;
        burnReward = theoreticalReward - mintReward;

        return (mintReward, burnReward);
    }

    function _calculateReward(
        uint256 round,
        address account
    ) internal view virtual override returns (uint256) {
        (uint256 mintReward, ) = _calculateRewardBreakdown(round, account);
        return mintReward;
    }

    function _claimReward(
        uint256 round
    ) internal virtual override returns (uint256 amount) {
        if (_claimedByAccount[round][msg.sender]) {
            revert AlreadyClaimed();
        }

        (uint256 mintReward, uint256 burnReward) = _calculateRewardBreakdown(
            round,
            msg.sender
        );
        amount = mintReward;

        _claimedByAccount[round][msg.sender] = true;
        _claimedRewardByAccount[round][msg.sender] = amount;
        _burnedRewardByAccount[round][msg.sender] = burnReward;

        if (amount > 0) {
            IERC20(TOKEN_ADDRESS).safeTransfer(msg.sender, amount);
        }

        if (burnReward > 0) {
            ILOVE20Token(TOKEN_ADDRESS).burn(burnReward);
            emit BurnReward({
                tokenAddress: TOKEN_ADDRESS,
                round: round,
                actionId: actionId,
                account: msg.sender,
                amount: burnReward
            });
        }

        emit ClaimReward({
            tokenAddress: TOKEN_ADDRESS,
            round: round,
            actionId: actionId,
            account: msg.sender,
            amount: amount
        });
    }

    function rewardInfoByAccount(
        uint256 round,
        address account
    )
        external
        view
        returns (uint256 mintReward, uint256 burnReward, bool isClaimed)
    {
        if (_claimedByAccount[round][account]) {
            return (
                _claimedRewardByAccount[round][account],
                _burnedRewardByAccount[round][account],
                true
            );
        }

        (mintReward, burnReward) = _calculateRewardBreakdown(round, account);
        return (mintReward, burnReward, false);
    }

    function _calculateBurnAmount(
        uint256 round,
        uint256 totalReward
    ) internal view virtual override returns (uint256) {
        if (totalReward == 0) return 0;

        uint256 totalJoined = _joinedAmountHistory.value(round);

        // If no one participated, burn all reward
        if (totalJoined == 0) {
            return totalReward;
        }

        // If someone participated, burning is handled by each participant during claim
        return 0;
    }

    function lastJoinedBlockByAccountByJoinedRound(
        address account,
        uint256 joinedRound
    ) external view returns (uint256 lastJoinedBlock) {
        return _lastJoinedBlockByAccountByJoinedRound[account][joinedRound];
    }
}
