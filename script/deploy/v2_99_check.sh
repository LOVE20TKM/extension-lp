#!/bin/bash

echo "========================================="
echo "Verifying Extension Factory Lp V2 Configuration"
echo "========================================="

if [ -z "$lpFactoryV2Address" ]; then
    echo -e "\033[31mError:\033[0m lpFactoryV2Address not set"
    echo "Please run: source ../network/$network/address.extension.lp.v2.params"
    return 1
fi

total_checks=0
passed_checks=0

total_checks=$((total_checks + 1))
actual_center=$(cast_call $lpFactoryV2Address "CENTER_ADDRESS()(address)")
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
