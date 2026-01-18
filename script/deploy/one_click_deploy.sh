#!/bin/bash

network=$1

echo "========================================="
echo "  One-Click Deploy Extension Factory Lp"
echo "  Network: $network"
echo "========================================="
echo ""

# Step 1: Initialize environment
echo "[Step 1/4] Initializing environment..."
source 00_init.sh $network || {
    echo -e "\033[31mError:\033[0m Failed to initialize environment"
    return 1
}
echo -e "\033[32m✓\033[0m Environment initialized"
echo ""

# Step 2: Deploy ExtensionLpFactory
echo "[Step 2/4] Deploying ExtensionLpFactory..."
source 01_deploy_extension_lp_factory.sh || {
    return 1
}
echo ""

# Step 4: Verify contract (if applicable)
echo "[Step 3/4] Contract verification..."
if [[ "$network" == thinkium* ]]; then
    source 03_verify.sh || {
        echo -e "\033[33mWarning:\033[0m Contract verification failed, but deployment was successful"
    }
else
    echo "Skipping contract verification (not a thinkium network)"
fi
echo ""

# Step 5: Run deployment checks
echo "[Step 4/4] Running deployment checks..."
source 99_check.sh || {
    echo -e "\033[33mWarning:\033[0m Some checks failed"
}
echo ""

echo "========================================="
echo -e "\033[32m✓\033[0m Deployment completed successfully!"
echo "========================================="
echo "Extension Factory Lp Address: $lpFactoryAddress"
echo "Network: $network"
echo "========================================="

