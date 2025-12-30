// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import "@extension/lib/core/script/BaseScript.sol";
import {ExtensionFactoryLp} from "../src/ExtensionFactoryLp.sol";

/**
 * @title DeployExtensionFactoryLp
 * @notice Script for deploying ExtensionFactoryLp contract
 * @dev Reads centerAddress from address.extension.center.params and writes deployed address to address.extension.factory.lp.params
 */
contract DeployExtensionFactoryLp is BaseScript {
    address public extensionFactoryLpAddress;

    /**
     * @notice Deploy ExtensionFactoryLp with centerAddress from address.extension.center.params
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

        // Deploy ExtensionFactoryLp
        vm.startBroadcast();
        extensionFactoryLpAddress = address(
            new ExtensionFactoryLp(centerAddress)
        );
        vm.stopBroadcast();

        // Log deployment info if enabled
        if (!hideLogs) {
            console.log(
                "ExtensionFactoryLp deployed at:",
                extensionFactoryLpAddress
            );
            console.log("Constructor parameters:");
            console.log("  centerAddress:", centerAddress);
        }

        // Update address file
        updateParamsFile(
            "address.extension.factory.lp.params",
            "extensionFactoryLpAddress",
            vm.toString(extensionFactoryLpAddress)
        );
    }
}
