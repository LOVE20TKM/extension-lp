// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface ILpFactory {
    function createExtension(
        address tokenAddress,
        address joinLpTokenAddress,
        uint256 govRatioMultiplier,
        uint256 minGovVotes
    ) external returns (address extension);
}
