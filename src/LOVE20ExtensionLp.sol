// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {ILOVE20ExtensionLp} from "./interface/ILOVE20ExtensionLp.sol";
import {
    LOVE20ExtensionBaseTokenJoinAuto
} from "@extension/src/LOVE20ExtensionBaseTokenJoinAuto.sol";
import {TokenJoin} from "@extension/src/base/TokenJoin.sol";
import {LOVE20ExtensionBase} from "@extension/src/LOVE20ExtensionBase.sol";
import {IAutoScore} from "@extension/src/interface/base/IAutoScore.sol";
import {
    ILOVE20ExtensionTokenJoinAuto
} from "@extension/src/interface/ILOVE20ExtensionTokenJoinAuto.sol";
import {ILOVE20Extension} from "@extension/src/interface/ILOVE20Extension.sol";
import {ITokenJoin} from "@extension/src/interface/base/ITokenJoin.sol";
import {
    ILOVE20ExtensionCenter
} from "@extension/src/interface/ILOVE20ExtensionCenter.sol";
import {
    IERC20
} from "@extension/lib/core/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {
    IUniswapV2Pair
} from "@core/uniswap-v2-core/interfaces/IUniswapV2Pair.sol";
import {
    EnumerableSet
} from "@extension/lib/core/lib/openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

contract LOVE20ExtensionLp is
    LOVE20ExtensionBaseTokenJoinAuto,
    ILOVE20ExtensionLp
{
    using EnumerableSet for EnumerableSet.AddressSet;
    // ============================================
    // STATE VARIABLES
    // ============================================

    uint256 public immutable govRatioMultiplier;
    uint256 public immutable lpRatioPrecision;
    uint256 public immutable minGovVotes;

    constructor(
        address factory_,
        address tokenAddress_,
        address joinTokenAddress_,
        uint256 waitingBlocks_,
        uint256 govRatioMultiplier_,
        uint256 minGovVotes_,
        uint256 lpRatioPrecision_
    )
        LOVE20ExtensionBaseTokenJoinAuto(
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
    ) public virtual override(ITokenJoin, LOVE20ExtensionBaseTokenJoinAuto) {
        // Check minimum governance votes requirement
        uint256 userGovVotes = _stake.validGovVotes(tokenAddress, msg.sender);
        if (userGovVotes < minGovVotes) {
            revert ILOVE20ExtensionLp.InsufficientGovVotes();
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
        return _lpToTokenAmount(totalJoinedAmount);
    }

    function joinedValueByAccount(
        address account
    ) external view returns (uint256) {
        ILOVE20ExtensionTokenJoinAuto.JoinInfo memory info = _joinInfo[account];
        return _lpToTokenAmount(info.amount);
    }

    // ============================================
    // ILOVE20ExtensionAutoScore IMPLEMENTATION
    // ============================================

    function calculateScore(
        address account
    )
        public
        view
        override(IAutoScore, LOVE20ExtensionBaseTokenJoinAuto)
        returns (uint256 total, uint256 score)
    {
        uint256[] memory scoresCalculated;
        (total, scoresCalculated) = calculateScores();
        score = 0;
        for (uint256 i = 0; i < scoresCalculated.length; i++) {
            if (_accounts.at(i) == account) {
                score = scoresCalculated[i];
                break;
            }
        }
        return (total, score);
    }

    function calculateScores()
        public
        view
        override(IAutoScore, LOVE20ExtensionBaseTokenJoinAuto)
        returns (uint256 totalCalculated, uint256[] memory scoresCalculated)
    {
        uint256 totalTokenSupply = _joinToken.totalSupply();
        uint256 totalGovVotes = _stake.govVotesNum(tokenAddress);

        if (totalTokenSupply == 0 || totalGovVotes == 0) {
            return (0, new uint256[](0));
        }

        uint256 accountsLength = _accounts.length();
        scoresCalculated = new uint256[](accountsLength);
        for (uint256 i = 0; i < accountsLength; i++) {
            address account = _accounts.at(i);
            uint256 joinedAmount = _joinInfo[account].amount;
            uint256 govVotes = _stake.validGovVotes(tokenAddress, account);

            uint256 score = (joinedAmount * lpRatioPrecision) /
                totalTokenSupply;
            if (govRatioMultiplier > 0) {
                uint256 govVotesRatio = (govVotes *
                    lpRatioPrecision *
                    govRatioMultiplier) / totalGovVotes;

                score = score > govVotesRatio ? govVotesRatio : score;
            }

            scoresCalculated[i] = score;
            totalCalculated += score;
        }
        return (totalCalculated, scoresCalculated);
    }
}
