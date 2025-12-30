// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IExtensionFactoryLp} from "./interface/IExtensionFactoryLp.sol";
import {ExtensionFactoryBase} from "@extension/src/ExtensionFactoryBase.sol";
import {ExtensionLp} from "./ExtensionLp.sol";

contract ExtensionFactoryLp is ExtensionFactoryBase, IExtensionFactoryLp {
    // ============================================
    // STATE VARIABLES
    // ============================================

    // extension => ExtensionParams
    mapping(address => ExtensionParams) internal _extensionParams;

    // ============================================
    // CONSTRUCTOR
    // ============================================

    constructor(address _center) ExtensionFactoryBase(_center) {}

    // ============================================
    // Lp FACTORY FUNCTIONS
    // ============================================
    function createExtension(
        address tokenAddress,
        address joinTokenAddress,
        uint256 waitingBlocks,
        uint256 govRatioMultiplier,
        uint256 minGovVotes
    ) external returns (address extension) {
        // Validate parameters
        if (joinTokenAddress == address(0)) {
            revert InvalidJoinTokenAddress();
        }

        extension = address(
            new ExtensionLp(
                address(this),
                tokenAddress,
                joinTokenAddress,
                waitingBlocks,
                govRatioMultiplier,
                minGovVotes
            )
        );

        // Store extension parameters
        _extensionParams[extension] = ExtensionParams({
            tokenAddress: tokenAddress,
            joinTokenAddress: joinTokenAddress,
            waitingBlocks: waitingBlocks,
            govRatioMultiplier: govRatioMultiplier,
            minGovVotes: minGovVotes
        });

        // Register extension and transfer initial tokens
        _registerExtension(extension, tokenAddress);

        emit ExtensionCreate(
            extension,
            tokenAddress,
            joinTokenAddress,
            waitingBlocks,
            govRatioMultiplier,
            minGovVotes
        );

        return extension;
    }

    /// @inheritdoc IExtensionFactoryLp
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
        )
    {
        ExtensionParams memory params = _extensionParams[extension];
        return (
            params.tokenAddress,
            params.joinTokenAddress,
            params.waitingBlocks,
            params.govRatioMultiplier,
            params.minGovVotes
        );
    }
}
