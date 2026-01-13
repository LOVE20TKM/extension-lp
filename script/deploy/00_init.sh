# ------ set network ------
export network=$1
if [ -z "$network" ] || [ ! -d "../network/$network" ]; then
    echo -e "\033[31mError:\033[0m Network parameter is required."
    echo -e "\nAvailable networks:"
    for net in $(ls ../network); do
        echo "  - $net"
    done
    return 1
fi

# ------ dont change below ------
network_dir="../network/$network"

source $network_dir/network.params && \
source $network_dir/LOVE20.params && \
source $network_dir/WETH.params && \
source $network_dir/address.params && \
source $network_dir/address.extension.center.params

# ------ Check .account file ------
if [ -f "$network_dir/.account" ]; then
    source $network_dir/.account
else
    echo -e "\033[33mWarning:\033[0m No .account file found at $network_dir/.account"
    echo "You need to set KEYSTORE_ACCOUNT and ACCOUNT_ADDRESS manually or create the .account file"
fi

# ------ Request keystore password ------
if [ ! -z "$KEYSTORE_ACCOUNT" ]; then
    echo -e "\nPlease enter keystore password (for $KEYSTORE_ACCOUNT):"
    read -s KEYSTORE_PASSWORD
    export KEYSTORE_PASSWORD
    echo "Password saved, will not be requested again in this session"
fi

cast_call() {
    local address=$1
    local function_signature=$2
    shift 2
    local args=("$@")

    # echo "Executing cast call: $address $function_signature ${args[@]}"
    cast call "$address" \
        "$function_signature" \
        "${args[@]}" \
        --rpc-url "$RPC_URL" \
        --account "$KEYSTORE_ACCOUNT" \
        --password "$KEYSTORE_PASSWORD"
}
echo "cast_call() loaded"

cast_send() {
    local address=$1
    local function_signature=$2
    shift 2
    local args=("$@")

    # echo "Executing cast send: $address $function_signature ${args[@]}"
    cast send "$address" \
        "$function_signature" \
        "${args[@]}" \
        --rpc-url "$RPC_URL" \
        --account "$KEYSTORE_ACCOUNT" \
        --password "$KEYSTORE_PASSWORD" \
        --legacy
}
echo "cast_send() loaded"

# Check if two values are equal
check_equal() {
    local description="$1"
    local expected="$2"
    local actual="$3"
    
    # Convert to lowercase for comparison
    expected=$(echo "$expected" | tr '[:upper:]' '[:lower:]')
    actual=$(echo "$actual" | tr '[:upper:]' '[:lower:]')
    
    if [ "$expected" = "$actual" ]; then
        echo -e "\033[32m✓\033[0m $description"
        echo -e "  Expected: $expected"
        echo -e "  Actual:   $actual"
        return 0
    else
        echo -e "\033[31m✗\033[0m $description"
        echo -e "  Expected: $expected"
        echo -e "  Actual:   $actual"
        return 1
    fi
}
echo "check_equal() loaded"


## Using keystore file method
forge_script() {
  forge script "$@" \
    --rpc-url $RPC_URL \
    --account $KEYSTORE_ACCOUNT \
    --sender $ACCOUNT_ADDRESS \
    --password "$KEYSTORE_PASSWORD" \
    --gas-price 5000000000 \
    --gas-limit 50000000 \
    --broadcast \
    --legacy \
    $([[ "$network" != "anvil" ]] && [[ "$network" != thinkium* ]] && echo "--verify --etherscan-api-key $ETHERSCAN_API_KEY")
}
echo "forge_script() loaded"

forge_script_deploy_extension_factory_lp() {
  forge_script ../DeployExtensionLpFactory.s.sol:DeployExtensionLpFactory --sig "run()"
}

echo "forge_script_deploy_extension_factory_lp() loaded"

