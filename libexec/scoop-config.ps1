# Usage: scoop config [rm] name [value]
# Summary: Get or set configuration values
# Help: The scoop configuration file is saved at ~/.scoop.
#
# To get a configuration setting:
#
#     scoop config <name>
#
# To set a configuration setting:
#
#     scoop config <name> <value>
#
# To remove a configuration setting:
#
#     scoop config rm <name>
#
# Settings
# --------
#
# proxy: [username:password@]host:port
#
# By default, Scoop will use the proxy settings from Internet Options, but with anonymous authentication.
#
# * To use the credentials for the current logged-in user, use 'currentuser' in place of username:password
# * To use the system proxy settings configured in Internet Options, use 'default' in place of host:port
# * An empty or unset value for proxy is equivalent to 'default' (with no username or password)
# * To bypass the system proxy and connect directly, use 'none' (with no username or password)

param($name, $value)

reset_aliases

if(!$name) { my_usage; exit 1 }

if($name -like 'rm') {
    set_config $value $null
} elseif($null -ne $value) {
    set_config $name $value
} else {
    get_config $name $value
}

exit 0
