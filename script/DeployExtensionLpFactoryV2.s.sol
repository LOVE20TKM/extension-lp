// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import "@extension/lib/core/script/BaseScript.sol";
import {ExtensionLpFactoryV2} from "../src/ExtensionLpFactoryV2.sol";

/**
 * @title DeployExtensionLpFactoryV2
 * @notice Script for deploying ExtensionLpFactoryV2 contract
 * @dev Reads centerAddress from address.extension.center.params and writes deployed address to address.extension.lp.v2.params
 */
contract DeployExtensionLpFactoryV2 is BaseScript {
    address public lpFactoryV2Address;

    function run() external {
        address centerAddress = readAddressParamsFile("address.extension.center.params", "centerAddress");

        require(centerAddress != address(0), "centerAddress not found");

        vm.startBroadcast();
        lpFactoryV2Address = address(new ExtensionLpFactoryV2(centerAddress));
        vm.stopBroadcast();

        if (!hideLogs) {
            console.log("ExtensionLpFactoryV2 deployed at:", lpFactoryV2Address);
            console.log("Constructor parameters:");
            console.log("  centerAddress:", centerAddress);
        }

        updateParamsFile("address.extension.lp.v2.params", "lpFactoryV2Address", vm.toString(lpFactoryV2Address));
    }
}
