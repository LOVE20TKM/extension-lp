// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface ILpFactory {
    error InvalidWaitingBlocks();

    function createExtension(
        address tokenAddress,
        address joinLpTokenAddress,
        uint256 waitingBlocks,
        uint256 govRatioMultiplier,
        uint256 minGovVotes
    ) external returns (address extension);
}
