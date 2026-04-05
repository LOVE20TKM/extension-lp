#!/bin/bash

network=$1

echo "========================================="
echo "  One-Click Deploy Extension Factory Lp V2"
echo "  Network: $network"
echo "========================================="
echo ""

echo "[Step 1/4] Initializing environment..."
source 00_init.sh $network || {
    echo -e "\033[31mError:\033[0m Failed to initialize environment"
    return 1
}
echo -e "\033[32m✓\033[0m Environment initialized"
echo ""

echo "[Step 2/4] Deploying ExtensionLpFactoryV2..."
source v2_01_deploy_extension_lp_factory.sh || {
    return 1
}
echo ""

echo "[Step 3/4] Contract verification..."
if [[ "$network" == thinkium* ]]; then
    source v2_03_verify.sh || {
        echo -e "\033[33mWarning:\033[0m Contract verification failed, but deployment was successful"
    }
else
    echo "Skipping contract verification (not a thinkium network)"
fi
echo ""

echo "[Step 4/4] Running deployment checks..."
source v2_99_check.sh || {
    echo -e "\033[33mWarning:\033[0m Some checks failed"
}
echo ""

echo "========================================="
echo -e "\033[32m✓\033[0m V2 deployment completed successfully!"
echo "========================================="
echo "Extension Factory Lp V2 Address: $lpFactoryV2Address"
echo "Network: $network"
echo "========================================="
