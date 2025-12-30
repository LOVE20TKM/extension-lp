// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {
    IExtensionFactory
} from "@extension/src/interface/IExtensionFactory.sol";

interface IExtensionFactoryLp is IExtensionFactory {
    error InvalidJoinTokenAddress();

    event ExtensionCreate(
        address extension,
        address tokenAddress,
        address joinTokenAddress,
        uint256 waitingBlocks,
        uint256 govRatioMultiplier,
        uint256 minGovVotes
    );

    function createExtension(
        address tokenAddress,
        address joinTokenAddress,
        uint256 waitingBlocks,
        uint256 govRatioMultiplier,
        uint256 minGovVotes
    ) external returns (address extension);
}
