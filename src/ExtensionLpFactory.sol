// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {ILpFactory} from "./interface/ILpFactory.sol";
import {ExtensionFactoryBase} from "@extension/src/ExtensionFactoryBase.sol";
import {ExtensionLp} from "./ExtensionLp.sol";
import {IExtensionCenter} from "@extension/src/interface/IExtensionCenter.sol";
import {
    IUniswapV2Pair
} from "@core/uniswap-v2-core/interfaces/IUniswapV2Pair.sol";

contract ExtensionLpFactory is ExtensionFactoryBase, ILpFactory {
    constructor(address _center) ExtensionFactoryBase(_center) {}

    function createExtension(
        address tokenAddress,
        address joinLpTokenAddress,
        uint256 waitingBlocks,
        uint256 govRatioMultiplier,
        uint256 minGovVotes
    ) external returns (address extension) {
        _validateJoinLpTokenAddress(tokenAddress, joinLpTokenAddress);

        extension = address(
            new ExtensionLp(
                address(this),
                tokenAddress,
                joinLpTokenAddress,
                waitingBlocks,
                govRatioMultiplier,
                minGovVotes
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
            revert InvalidJoinTokenAddress();
        }

        IExtensionCenter center = IExtensionCenter(CENTER_ADDRESS);
        address uniswapV2FactoryAddress = center.uniswapV2FactoryAddress();

        try IUniswapV2Pair(joinLpTokenAddress).factory() returns (
            address pairFactory
        ) {
            if (pairFactory != uniswapV2FactoryAddress) {
                revert InvalidJoinTokenAddress();
            }
        } catch {
            revert InvalidJoinTokenAddress();
        }
        address pairToken0;
        address pairToken1;
        try IUniswapV2Pair(joinLpTokenAddress).token0() returns (
            address token0
        ) {
            pairToken0 = token0;
        } catch {
            revert InvalidJoinTokenAddress();
        }
        try IUniswapV2Pair(joinLpTokenAddress).token1() returns (
            address token1
        ) {
            pairToken1 = token1;
        } catch {
            revert InvalidJoinTokenAddress();
        }
        if (pairToken0 != tokenAddress && pairToken1 != tokenAddress) {
            revert InvalidJoinTokenAddress();
        }
    }
}
