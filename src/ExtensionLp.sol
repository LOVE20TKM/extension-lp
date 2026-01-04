// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {ExtensionCore} from "@extension/src/ExtensionCore.sol";
import {IExtensionCore} from "@extension/src/interface/IExtensionCore.sol";
import {IExtensionLp} from "./interface/IExtensionLp.sol";
import {
    ExtensionBaseRewardTokenJoin
} from "@extension/src/ExtensionBaseRewardTokenJoin.sol";
import {ITokenJoin} from "@extension/src/interface/ITokenJoin.sol";
import {IExtensionCenter} from "@extension/src/interface/IExtensionCenter.sol";
import {
    IUniswapV2Pair
} from "@core/uniswap-v2-core/interfaces/IUniswapV2Pair.sol";
import {RoundHistoryUint256} from "@extension/src/lib/RoundHistoryUint256.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ILOVE20Token} from "@core/interfaces/ILOVE20Token.sol";
import {ILOVE20Stake} from "@core/interfaces/ILOVE20Stake.sol";

using RoundHistoryUint256 for RoundHistoryUint256.History;
using SafeERC20 for IERC20;

contract ExtensionLp is ExtensionBaseRewardTokenJoin, IExtensionLp {
    uint256 internal constant LP_RATIO_PRECISION = 1e18;

    uint256 public immutable GOV_RATIO_MULTIPLIER;
    uint256 public immutable MIN_GOV_VOTES;

    ILOVE20Stake internal immutable _stake;

    /// @dev round => account => burnReward (recorded at claim time)
    mapping(uint256 => mapping(address => uint256)) internal _burnReward;

    constructor(
        address factory_,
        address tokenAddress_,
        address joinTokenAddress_,
        uint256 waitingBlocks_,
        uint256 govRatioMultiplier_,
        uint256 minGovVotes_
    )
        ExtensionBaseRewardTokenJoin(
            factory_,
            tokenAddress_,
            joinTokenAddress_,
            waitingBlocks_
        )
    {
        GOV_RATIO_MULTIPLIER = govRatioMultiplier_;
        MIN_GOV_VOTES = minGovVotes_;
        _stake = ILOVE20Stake(_center.stakeAddress());
        _validateJoinToken();
    }

    function join(
        uint256 amount,
        string[] memory verificationInfos
    ) public virtual override(ExtensionBaseRewardTokenJoin, ITokenJoin) {
        bool isFirstJoin = _joinedBlockByAccount[msg.sender] == 0;

        if (isFirstJoin) {
            uint256 userGovVotes = _stake.validGovVotes(
                TOKEN_ADDRESS,
                msg.sender
            );
            if (userGovVotes < MIN_GOV_VOTES) {
                revert InsufficientGovVotes();
            }
        }

        super.join(amount, verificationInfos);
    }

    function _validateJoinToken() internal view {
        address uniswapV2FactoryAddress = _center.uniswapV2FactoryAddress();

        try IUniswapV2Pair(joinTokenAddress).factory() returns (
            address pairFactory
        ) {
            if (pairFactory != uniswapV2FactoryAddress) {
                revert ITokenJoin.InvalidJoinTokenAddress();
            }
        } catch {
            revert ITokenJoin.InvalidJoinTokenAddress();
        }
        address pairToken0;
        address pairToken1;
        try IUniswapV2Pair(joinTokenAddress).token0() returns (address token0) {
            pairToken0 = token0;
        } catch {
            revert ITokenJoin.InvalidJoinTokenAddress();
        }
        try IUniswapV2Pair(joinTokenAddress).token1() returns (address token1) {
            pairToken1 = token1;
        } catch {
            revert ITokenJoin.InvalidJoinTokenAddress();
        }
        if (pairToken0 != TOKEN_ADDRESS && pairToken1 != TOKEN_ADDRESS) {
            revert ITokenJoin.InvalidJoinTokenAddress();
        }
    }

    function isJoinedValueConverted()
        external
        pure
        override(ExtensionCore)
        returns (bool)
    {
        return true;
    }

    function _lpToTokenAmount(
        uint256 lpAmount
    ) internal view returns (uint256) {
        if (lpAmount == 0) {
            return 0;
        }

        IUniswapV2Pair pair = IUniswapV2Pair(joinTokenAddress);

        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        uint256 totalLp = pair.totalSupply();

        if (totalLp == 0) {
            return 0;
        }

        address pairToken0 = pair.token0();
        uint256 tokenReserve = (pairToken0 == TOKEN_ADDRESS)
            ? uint256(reserve0)
            : uint256(reserve1);

        return (lpAmount * tokenReserve) / totalLp;
    }

    function joinedValue()
        external
        view
        override(ExtensionCore)
        returns (uint256)
    {
        return _lpToTokenAmount(totalJoinedAmount());
    }

    function joinedValueByAccount(
        address account
    ) external view override(ExtensionCore) returns (uint256) {
        return _lpToTokenAmount(_amountHistoryByAccount[account].latestValue());
    }

    function _calculateRewards(
        uint256 round,
        address account
    ) internal view returns (uint256 mintReward, uint256 burnReward) {
        if (round >= _verify.currentRound()) {
            return (0, 0);
        }

        (uint256 totalActionReward, ) = _mint.actionRewardByActionIdByAccount(
            TOKEN_ADDRESS,
            round,
            actionId,
            address(this)
        );

        if (totalActionReward == 0) {
            return (0, 0);
        }

        uint256 joinedAmount = amountByAccountByRound(account, round);
        uint256 totalJoined = totalJoinedAmountByRound(round);

        if (totalJoined == 0 || joinedAmount == 0) {
            return (0, 0);
        }

        uint256 tokenRatio = (joinedAmount * LP_RATIO_PRECISION) / totalJoined;
        uint256 theoreticalReward = (totalActionReward * tokenRatio) /
            LP_RATIO_PRECISION;

        uint256 ratio = tokenRatio;
        if (GOV_RATIO_MULTIPLIER > 0) {
            uint256 totalGovVotes = _stake.govVotesNum(TOKEN_ADDRESS);
            if (totalGovVotes == 0) {
                return (0, 0);
            }
            uint256 govVotes = _stake.validGovVotes(TOKEN_ADDRESS, account);
            uint256 govVotesRatio = (govVotes *
                LP_RATIO_PRECISION *
                GOV_RATIO_MULTIPLIER) / totalGovVotes;
            if (govVotesRatio < tokenRatio) {
                ratio = govVotesRatio;
            }
        }

        mintReward = (totalActionReward * ratio) / LP_RATIO_PRECISION;
        burnReward = theoreticalReward > mintReward
            ? theoreticalReward - mintReward
            : 0;
    }

    function _calculateReward(
        uint256 round,
        address account
    ) internal view virtual override returns (uint256) {
        (uint256 mintReward, ) = _calculateRewards(round, account);
        return mintReward;
    }

    function _claimReward(
        uint256 round
    ) internal virtual override returns (uint256 amount) {
        if (_claimedReward[round][msg.sender] > 0) {
            revert AlreadyClaimed();
        }

        (uint256 mintReward, uint256 burnReward) = _calculateRewards(
            round,
            msg.sender
        );
        amount = mintReward;

        _claimedReward[round][msg.sender] = amount;
        _burnReward[round][msg.sender] = burnReward;

        if (amount > 0) {
            IERC20(TOKEN_ADDRESS).safeTransfer(msg.sender, amount);
        }

        if (burnReward > 0) {
            ILOVE20Token(TOKEN_ADDRESS).burn(burnReward);
            emit IExtensionLp.BurnReward(
                TOKEN_ADDRESS,
                round,
                actionId,
                msg.sender,
                burnReward
            );
        }

        emit ClaimReward(TOKEN_ADDRESS, round, actionId, msg.sender, amount);
    }

    function rewardInfoByAccount(
        uint256 round,
        address account
    )
        external
        view
        returns (uint256 mintReward, uint256 burnReward, bool isMinted)
    {
        uint256 claimedReward = _claimedReward[round][account];
        if (claimedReward > 0) {
            return (claimedReward, _burnReward[round][account], true);
        }

        (mintReward, burnReward) = _calculateRewards(round, account);
    }
}
