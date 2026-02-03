// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface ILpErrors {
    error InsufficientGovVotes();
}

interface ILp is ILpErrors {
    function GOV_RATIO_MULTIPLIER() external view returns (uint256);

    function MIN_GOV_VOTES() external view returns (uint256);

    function lastJoinedBlockByAccountByJoinedRound(
        address account,
        uint256 joinedRound
    ) external view returns (uint256 lastJoinedBlock);
}
