// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {ILOVE20ExtensionLp} from "./interface/ILOVE20ExtensionLp.sol";
import {
    LOVE20ExtensionBaseTokenJoin
} from "@extension/src/LOVE20ExtensionBaseTokenJoin.sol";
import {TokenJoin} from "@extension/src/base/TokenJoin.sol";
import {ExtensionReward} from "@extension/src/base/ExtensionReward.sol";
import {
    IExtensionReward
} from "@extension/src/interface/base/IExtensionReward.sol";
import {ITokenJoin} from "@extension/src/interface/base/ITokenJoin.sol";
import {
    ILOVE20ExtensionCenter
} from "@extension/src/interface/ILOVE20ExtensionCenter.sol";
import {
    IUniswapV2Pair
} from "@core/uniswap-v2-core/interfaces/IUniswapV2Pair.sol";
import {RoundHistoryUint256} from "@extension/src/lib/RoundHistoryUint256.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

using RoundHistoryUint256 for RoundHistoryUint256.History;
using SafeERC20 for IERC20;

contract LOVE20ExtensionLp is LOVE20ExtensionBaseTokenJoin, ILOVE20ExtensionLp {
    // ============================================
    // STATE VARIABLES
    // ============================================

    uint256 public immutable govRatioMultiplier;
    uint256 public immutable lpRatioPrecision;
    uint256 public immutable minGovVotes;

    /// @dev round => account => burnReward (recorded at claim time)
    mapping(uint256 => mapping(address => uint256)) internal _burnReward;

    constructor(
        address factory_,
        address tokenAddress_,
        address joinTokenAddress_,
        uint256 waitingBlocks_,
        uint256 govRatioMultiplier_,
        uint256 minGovVotes_,
        uint256 lpRatioPrecision_
    )
        LOVE20ExtensionBaseTokenJoin(
            factory_,
            tokenAddress_,
            joinTokenAddress_,
            waitingBlocks_
        )
    {
        govRatioMultiplier = govRatioMultiplier_;
        minGovVotes = minGovVotes_;
        lpRatioPrecision = lpRatioPrecision_;
        _validateJoinToken();
    }

    function join(
        uint256 amount,
        string[] memory verificationInfos
    ) public virtual override(ITokenJoin, TokenJoin) {
        bool isFirstJoin = _joinedBlockByAccount[msg.sender] == 0;

        // Check minimum governance votes requirement only on first join
        if (isFirstJoin) {
            uint256 userGovVotes = _stake.validGovVotes(
                tokenAddress,
                msg.sender
            );
            if (userGovVotes < minGovVotes) {
                revert ILOVE20ExtensionLp.InsufficientGovVotes();
            }
        }

        // Validate LP ratio before joining
        if (lpRatioPrecision > 0) {
            uint256 totalLpSupply = _joinToken.totalSupply();
            if (totalLpSupply > 0) {
                uint256 lpRatio = (amount * lpRatioPrecision) / totalLpSupply;
                if (lpRatio < 1) {
                    revert ILOVE20ExtensionLp.InsufficientLpRatio();
                }
            }
        }

        // Call parent join function
        super.join(amount, verificationInfos);
    }

    function _validateJoinToken() internal view {
        address uniswapV2FactoryAddress = ILOVE20ExtensionCenter(center())
            .uniswapV2FactoryAddress();

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
        if (pairToken0 != tokenAddress && pairToken1 != tokenAddress) {
            revert ITokenJoin.InvalidJoinTokenAddress();
        }
    }

    // ============================================
    // ILOVE20EXTENSION INTERFACE IMPLEMENTATION
    // ============================================

    function isJoinedValueCalculated() external pure returns (bool) {
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
        uint256 tokenReserve = (pairToken0 == tokenAddress)
            ? uint256(reserve0)
            : uint256(reserve1);

        return (lpAmount * tokenReserve) / totalLp;
    }

    function joinedValue() external view returns (uint256) {
        return _lpToTokenAmount(totalJoinedAmount());
    }

    function joinedValueByAccount(
        address account
    ) external view returns (uint256) {
        return _lpToTokenAmount(_amountHistoryByAccount[account].latestValue());
    }

    // ============================================
    // REWARD CALCULATION
    // ============================================

    /// @dev Calculate both mintReward and burnReward for an account in a specific round
    function _calculateRewards(
        uint256 round,
        address account
    ) internal view returns (uint256 mintReward, uint256 burnReward) {
        if (round >= _verify.currentRound()) {
            return (0, 0);
        }

        (uint256 totalActionReward, ) = _mint.actionRewardByActionIdByAccount(
            tokenAddress,
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

        // tokenRatio = joinedAmount / totalJoined (scaled by lpRatioPrecision)
        uint256 tokenRatio = (joinedAmount * lpRatioPrecision) / totalJoined;
        uint256 theoreticalReward = (totalActionReward * tokenRatio) /
            lpRatioPrecision;

        // Calculate score (may be limited by gov votes)
        uint256 score = tokenRatio;
        if (govRatioMultiplier > 0) {
            uint256 totalGovVotes = _stake.govVotesNum(tokenAddress);
            if (totalGovVotes == 0) {
                return (0, 0);
            }
            uint256 govVotes = _stake.validGovVotes(tokenAddress, account);
            uint256 govVotesRatio = (govVotes *
                lpRatioPrecision *
                govRatioMultiplier) / totalGovVotes;
            if (govVotesRatio < tokenRatio) {
                score = govVotesRatio;
            }
        }

        mintReward = (totalActionReward * score) / lpRatioPrecision;
        burnReward = theoreticalReward > mintReward
            ? theoreticalReward - mintReward
            : 0;
    }

    /// @dev Calculate reward for an account (interface compatibility)
    function _calculateReward(
        uint256 round,
        address account
    ) internal view virtual override returns (uint256) {
        (uint256 mintReward, ) = _calculateRewards(round, account);
        return mintReward;
    }

    /// @dev Override to record burnReward at claim time
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
            IERC20(tokenAddress).safeTransfer(msg.sender, amount);
        }

        emit ClaimReward(tokenAddress, round, actionId, msg.sender, amount);
    }

    /// @notice Get reward info for an account in a specific round
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
