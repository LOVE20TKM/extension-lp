#!/bin/bash

# Ensure environment is initialized
if [ -z "$RPC_URL" ]; then
    echo -e "\033[31mError:\033[0m Environment not initialized. Run 'source 00_init.sh <network>' first."
    return 1
fi

echo "Deploying ExtensionLpFactoryV2..."
forge_script ../DeployExtensionLpFactoryV2.s.sol:DeployExtensionLpFactoryV2 --sig "run()" || {
    echo -e "\033[31mError:\033[0m Deployment failed"
    return 1
}

source $network_dir/address.extension.lp.v2.params
echo -e "\033[32m✓\033[0m ExtensionLpFactoryV2 deployed at: $lpFactoryV2Address"
