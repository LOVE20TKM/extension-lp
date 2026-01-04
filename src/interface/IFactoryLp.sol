// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface IFactoryLp {
    error InvalidJoinTokenAddress();

    function createExtension(
        address tokenAddress,
        address joinTokenAddress,
        uint256 waitingBlocks,
        uint256 govRatioMultiplier,
        uint256 minGovVotes
    ) external returns (address extension);
}
