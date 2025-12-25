// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {
    ILOVE20ExtensionFactory
} from "@extension/src/interface/ILOVE20ExtensionFactory.sol";

interface ILOVE20ExtensionFactoryLp is ILOVE20ExtensionFactory {
    /// @notice Extension creation parameters
    struct ExtensionParams {
        address tokenAddress; // Token address
        address joinTokenAddress; // Token address for joining actions
        uint256 waitingBlocks; // Number of blocks to wait before unstaking
        uint256 govRatioMultiplier; // Governance ratio multiplier
        uint256 minGovVotes; // Minimum governance votes required
    }

    // ============================================
    // ERRORS
    // ============================================

    error InvalidJoinTokenAddress();

    // ============================================
    // EVENTS
    // ============================================

    event ExtensionCreated(
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

    /// @notice Get extension parameters
    /// @param extension The extension address
    /// @return tokenAddress The token address
    /// @return joinTokenAddress The join token address for participating in actions
    /// @return waitingBlocks The waiting blocks for unstaking
    /// @return govRatioMultiplier The governance ratio multiplier
    /// @return minGovVotes The minimum governance votes required
    function extensionParams(
        address extension
    )
        external
        view
        returns (
            address tokenAddress,
            address joinTokenAddress,
            uint256 waitingBlocks,
            uint256 govRatioMultiplier,
            uint256 minGovVotes
        );
}
