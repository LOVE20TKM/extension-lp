// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface ILp {
    error InsufficientGovVotes();

    event BurnReward(
        address indexed tokenAddress,
        uint256 round,
        uint256 indexed actionId,
        address indexed account,
        uint256 amount
    );

    function GOV_RATIO_MULTIPLIER() external view returns (uint256);

    function MIN_GOV_VOTES() external view returns (uint256);

    function rewardInfoByAccount(
        uint256 round,
        address account
    )
        external
        view
        returns (uint256 mintReward, uint256 burnReward, bool isClaimed);
}
