#!/bin/bash

echo "========================================="
echo "Verifying Extension Factory Lp Configuration"
echo "========================================="

if [ -z "$extensionFactoryLpAddress" ]; then
    echo -e "\033[31mError:\033[0m extensionFactoryLpAddress not set"
    echo "Please run: source ../network/$network/address.extension.factory.lp.params"
    return 1
fi

# Initialize counters
total_checks=0
passed_checks=0

# Check 1: Verify center address
total_checks=$((total_checks + 1))
actual_center=$(cast call $extensionFactoryLpAddress "center()(address)" --rpc-url $RPC_URL)
if check_equal "Center address" "$centerAddress" "$actual_center"; then
    passed_checks=$((passed_checks + 1))
fi

echo ""
echo "========================================="
if [ $passed_checks -eq $total_checks ]; then
    echo -e "\033[32m✓\033[0m All checks passed ($passed_checks/$total_checks)"
else
    failed=$((total_checks - passed_checks))
    echo -e "\033[31m✗\033[0m $failed check(s) failed ($passed_checks/$total_checks passed)"
    return 1
fi
echo "========================================="

