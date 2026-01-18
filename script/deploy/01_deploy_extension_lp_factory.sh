#!/bin/bash

# Ensure environment is initialized
if [ -z "$RPC_URL" ]; then
    echo -e "\033[31mError:\033[0m Environment not initialized. Run 'source 00_init.sh <network>' first."
    return 1
fi

echo "Deploying ExtensionLpFactory..."
forge_script_deploy_extension_factory_lp || {
    echo -e "\033[31mError:\033[0m Deployment failed"
    return 1
}

# Load and display deployed address
source $network_dir/address.extension.lp.params
echo -e "\033[32m✓\033[0m ExtensionLpFactory deployed at: $lpFactoryAddress"
