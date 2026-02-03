// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {ILpFactory, ILpFactoryErrors} from "./interface/ILpFactory.sol";
import {ExtensionLp} from "./ExtensionLp.sol";
import {ExtensionFactoryBase} from "@extension/src/ExtensionFactoryBase.sol";
import {IExtensionCenter} from "@extension/src/interface/IExtensionCenter.sol";
import {ITokenJoinErrors} from "@extension/src/interface/ITokenJoin.sol";
import {TokenLib} from "@extension/src/lib/TokenLib.sol";

contract ExtensionLpFactory is ExtensionFactoryBase, ILpFactory {
    constructor(address _center) ExtensionFactoryBase(_center) {}

    function createExtension(
        address tokenAddress,
        address joinLpTokenAddress,
        uint256 govRatioMultiplier,
        uint256 minGovRatio
    ) external returns (address extension) {
        _validateJoinLpTokenAddress(tokenAddress, joinLpTokenAddress);

        extension = address(
            new ExtensionLp(
                address(this),
                tokenAddress,
                joinLpTokenAddress,
                govRatioMultiplier,
                minGovRatio
            )
        );

        _registerExtension(extension, tokenAddress);

        return extension;
    }

    function _validateJoinLpTokenAddress(
        address tokenAddress,
        address joinLpTokenAddress
    ) internal view {
        if (joinLpTokenAddress == address(0)) {
            revert ITokenJoinErrors.InvalidJoinTokenAddress();
        }

        IExtensionCenter center = IExtensionCenter(CENTER_ADDRESS);
        address uniswapV2FactoryAddress = center.uniswapV2FactoryAddress();

        if (
            !TokenLib.isLpTokenFromFactory(
                joinLpTokenAddress,
                uniswapV2FactoryAddress
            )
        ) {
            revert ILpFactoryErrors.InvalidJoinTokenFactory();
        }

        if (
            !TokenLib.isLpTokenContainsToken(joinLpTokenAddress, tokenAddress)
        ) {
            revert ILpFactoryErrors.InvalidJoinTokenPair();
        }
    }
}
