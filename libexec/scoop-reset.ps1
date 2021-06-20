# Usage: scoop reset <app>
# Summary: Reset an app to resolve conflicts
# Help: Used to resolve conflicts in favor of a particular app. For example,
# if you've installed 'python' and 'python27', you can use 'scoop reset' to switch between
# using one or the other.

. "$psscriptroot\..\lib\core.ps1"
. "$psscriptroot\..\lib\manifest.ps1"
. "$psscriptroot\..\lib\help.ps1"
. "$psscriptroot\..\lib\getopt.ps1"
. "$psscriptroot\..\lib\install.ps1"
. "$psscriptroot\..\lib\versions.ps1"
. "$psscriptroot\..\lib\shortcuts.ps1"

reset_aliases
$opt, $apps, $err = getopt $args
if($err) { "scoop reset: $err"; exit 1 }

if(!$apps) { error '<app> missing'; my_usage; exit 1 }

if($apps -eq '*') {
    $local = installed_apps $false | ForEach-Object { ,@($_, $false) }
    $global = installed_apps $true | ForEach-Object { ,@($_, $true) }
    $apps = @($local) + @($global)
}

$apps | ForEach-Object {
    ($app, $global) = $_

    $app, $bucket, $version = parse_app $app

    if(($global -eq $null) -and (installed $app $true)) {
        # set global flag when running reset command on specific app
        $global = $true
    }

    if($app -eq 'scoop') {
        # skip scoop
        return
    }

    if(!(installed $app)) {
        error "'$app' isn't installed"
        return
    }

    if ($null -eq $version) {
        $version = current_version $app $global
    }

    $manifest = installed_manifest $app $version $global
    # if this is null we know the version they're resetting to
    # is not installed
    if ($manifest -eq $null) {
        error "'$app ($version)' isn't installed"
        return
    }

    if($global -and !(is_admin)) {
        warn "'$app' ($version) is a global app. You need admin rights to reset it. Skipping."
        return
    }

    write-host "Resetting $app ($version)."

    $dir = resolve-path (versiondir $app $version $global)
    $original_dir = $dir
    $persist_dir = persistdir $app $global

    #region Workaround for #2952
    $processdir = $dir | Select-Object -ExpandProperty Path
    if (Get-Process | Where-Object { $_.Path -like "$processdir\*" }) {
        error "Application is still running. Close all instances and try again."
        continue
    }
    #endregion Workaround for #2952

    $install = install_info $app $version $global
    $architecture = $install.architecture

    $dir = link_current $dir
    create_shims $manifest $dir $global $architecture
    create_startmenu_shortcuts $manifest $dir $global $architecture
    env_add_path $manifest $dir
    env_set $manifest $dir $global
    # unlink all potential old link before re-persisting
    unlink_persist_data $original_dir
    persist_data $manifest $original_dir $persist_dir
    persist_permission $manifest $global
}

exit 0
