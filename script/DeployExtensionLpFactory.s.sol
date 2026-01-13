// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import "@extension/lib/core/script/BaseScript.sol";
import {ExtensionLpFactory} from "../src/ExtensionLpFactory.sol";

/**
 * @title DeployExtensionLpFactory
 * @notice Script for deploying ExtensionLpFactory contract
 * @dev Reads centerAddress from address.extension.center.params and writes deployed address to address.extension.factory.lp.params
 */
contract DeployExtensionLpFactory is BaseScript {
    address public lpFactoryAddress;

    /**
     * @notice Deploy ExtensionLpFactory with centerAddress from address.extension.center.params
     * @dev The required center address is read from the network's address.extension.center.params file
     */
    function run() external {
        // Read centerAddress from address.extension.center.params
        address centerAddress = readAddressParamsFile(
            "address.extension.center.params",
            "centerAddress"
        );

        // Validate address
        require(centerAddress != address(0), "centerAddress not found");

        // Deploy ExtensionLpFactory
        vm.startBroadcast();
        lpFactoryAddress = address(new ExtensionLpFactory(centerAddress));
        vm.stopBroadcast();

        // Log deployment info if enabled
        if (!hideLogs) {
            console.log("ExtensionLpFactory deployed at:", lpFactoryAddress);
            console.log("Constructor parameters:");
            console.log("  centerAddress:", centerAddress);
        }

        // Update address file
        updateParamsFile(
            "address.extension.lp.params",
            "lpFactoryAddress",
            vm.toString(lpFactoryAddress)
        );
    }
}
