// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {
    IExtensionTokenJoin
} from "@extension/src/interface/IExtensionTokenJoin.sol";

interface IExtensionLp is IExtensionTokenJoin {
    // Lp-specific errors (InvalidJoinTokenAddress is inherited from ITokenJoin)
    error InsufficientGovVotes();

    // Lp-specific events
    event BurnReward(
        address indexed tokenAddress,
        uint256 round,
        uint256 indexed actionId,
        address indexed account,
        uint256 amount
    );

    // Lp-specific config
    function govRatioMultiplier() external view returns (uint256);
    function minGovVotes() external view returns (uint256);

    /// @notice Get reward info for an account in a specific round
    /// @param round The round number
    /// @param account The account address
    /// @return mintReward The actual reward amount (after overflow burned)
    /// @return burnReward The burned (overflow) reward amount
    /// @return isMinted Whether the reward has been claimed
    function rewardInfoByAccount(
        uint256 round,
        address account
    )
        external
        view
        returns (uint256 mintReward, uint256 burnReward, bool isMinted);
}
