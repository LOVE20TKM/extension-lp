// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface ILpFactoryErrors {
    error InvalidJoinTokenFactory();
    error InvalidJoinTokenPair();
}

interface ILpFactory is ILpFactoryErrors {
    function createExtension(
        address tokenAddress,
        address joinLpTokenAddress,
        uint256 govRatioMultiplier,
        uint256 minGovVotes
    ) external returns (address extension);
}
