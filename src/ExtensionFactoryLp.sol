// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IExtensionFactoryLp} from "./interface/IExtensionFactoryLp.sol";
import {ExtensionFactoryBase} from "@extension/src/ExtensionFactoryBase.sol";
import {ExtensionLp} from "./ExtensionLp.sol";

contract ExtensionFactoryLp is ExtensionFactoryBase, IExtensionFactoryLp {
    constructor(address _center) ExtensionFactoryBase(_center) {}

    function createExtension(
        address tokenAddress,
        address joinTokenAddress,
        uint256 waitingBlocks,
        uint256 govRatioMultiplier,
        uint256 minGovVotes
    ) external returns (address extension) {
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

        _registerExtension(extension, tokenAddress);

        return extension;
    }
}
