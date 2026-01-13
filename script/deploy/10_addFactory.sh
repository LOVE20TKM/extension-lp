source $network_dir/address.extension.center.params
source $network_dir/address.extension.lp.params

cast_send $centerAddress "addFactory(address,address)()" $firstTokenAddress $lpFactoryAddress