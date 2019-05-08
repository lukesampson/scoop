# Usage: scoop cleanup <app> [options]
# Summary: Cleanup apps by removing old versions
# Help: 'scoop cleanup' cleans Scoop apps by removing old versions.
# 'scoop cleanup <app>' cleans up the old versions of that app if said versions exist.
#
# You can use '*' in place of <app> to cleanup all apps.
#
# Options:
#   -g, --global       Cleanup a globally installed app
#   -k, --cache        Remove outdated download cache

reset_aliases

$opt, $apps, $err = getopt $args 'gk' 'global', 'cache'
if ($err) { "scoop cleanup: $err"; exit 1 }
$global = $opt.g -or $opt.global
$cache = $opt.k -or $opt.cache

if (!$apps) { 'ERROR: <app> missing'; my_usage; exit 1 }

if ($global -and !(is_admin)) {
    'ERROR: you need admin rights to cleanup global apps'; exit 1
}

function cleanup($app, $global, $verbose, $cache) {
    $current_version = current_version $app $global
    if ($cache) {
        Remove-Item "$cachedir\$app#*" -Exclude "$app#$current_version#*"
    }
    $versions = versions $app $global | Where-Object { $_ -ne $current_version -and $_ -ne 'current' }
    if (!$versions) {
        if ($verbose) { success "$app is already clean" }
        return
    }

    write-host -f yellow "Removing $app`:" -nonewline
    $versions | ForEach-Object {
        $version = $_
        write-host " $version" -nonewline
        $dir = versiondir $app $version $global
        # unlink all potential old link before doing recursive Remove-Item
        unlink_persist_data $dir
        Remove-Item $dir -ErrorAction Stop -Recurse -Force
    }
    write-host ''
}

if ($apps) {
    $verbose = $true
    if ($apps -eq '*') {
        $verbose = $false
        $apps = applist (installed_apps $false) $false
        if ($global) {
            $apps += applist (installed_apps $true) $true
        }
    } else {
        $apps = Confirm-InstallationStatus $apps -Global:$global
    }

    # $apps is now a list of ($app, $global) tuples
    $apps | ForEach-Object { cleanup @_ $verbose $cache}

    if ($cache) {
        Remove-Item "$cachedir\*.download" -ErrorAction Ignore
    }

    if (!$verbose) {
        success 'Everything is shiny now!'
    }
}

exit 0
