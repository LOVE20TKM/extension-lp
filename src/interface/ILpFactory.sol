// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface ILpFactoryErrors {
    error InvalidWaitingBlocks();
}

interface ILpFactory is ILpFactoryErrors {
    function createExtension(
        address tokenAddress,
        address joinLpTokenAddress,
        uint256 waitingBlocks,
        uint256 govRatioMultiplier,
        uint256 minGovVotes
    ) external returns (address extension);
}
