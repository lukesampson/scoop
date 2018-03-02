# Usage: scoop uninstall <app> [options]
# Summary: Uninstall an app
# Help: e.g. scoop uninstall git
#
# Options:
#   -g, --global   Uninstall a globally installed app
#   -p, --purge    Remove all persistent data
. "$psscriptroot\..\lib\core.ps1"
. "$psscriptroot\..\lib\manifest.ps1"
. "$psscriptroot\..\lib\help.ps1"
. "$psscriptroot\..\lib\install.ps1"
. "$psscriptroot\..\lib\shortcuts.ps1"
. "$psscriptroot\..\lib\psmodules.ps1"
. "$psscriptroot\..\lib\versions.ps1"
. "$psscriptroot\..\lib\getopt.ps1"
. "$psscriptroot\..\lib\config.ps1"

reset_aliases

# options
$opt, $apps, $err = getopt $args 'gp' 'global', 'purge'
if($err) { "scoop uninstall: $err"; exit 1 }
$global = $opt.g -or $opt.global
$purge = $opt.p -or $opt.purge

if(!$apps) { 'ERROR: <app> missing'; my_usage; exit 1 }

if($global -and !(is_admin)) {
    'ERROR: You need admin rights to uninstall global apps.'; exit 1
}

if($apps -eq 'scoop') {
    & "$psscriptroot\..\bin\uninstall.ps1" $global; exit
}

$apps = ensure_all_installed $apps $global
if(!$apps) { exit 0 }

$apps | % {
    ($app, $global) = $_

    $version = current_version $app $global
    write-host "Uninstalling '$app' ($version)."

    $dir = versiondir $app $version $global
    $persist_dir = persistdir $app $global

    try {
        test-path $dir -ea stop | out-null
    } catch [unauthorizedaccessexception] {
        error "Access denied: $dir. You might need to restart."
        continue
    }

    $manifest = installed_manifest $app $version $global
    $install = install_info $app $version $global
    $architecture = $install.architecture

    run_uninstaller $manifest $architecture $dir $install.bucket
    rm_shims $manifest $global $architecture
    rm_startmenu_shortcuts $manifest $global $architecture

    # If a junction was used during install, that will have been used
    # as the reference directory. Otherwise it will just be the version
    # directory.
    $refdir = unlink_current $dir

    uninstall_psmodule $manifest $refdir $global

    env_rm_path $manifest $refdir $global
    env_rm $manifest $global

    try {
        rm -r $dir -ea stop -force
    } catch {
        error "Couldn't remove '$(friendly_path $dir)'; it may be in use."
        continue
    }

    # remove older versions
    $old = @(versions $app $global)
    foreach($oldver in $old) {
        write-host "Removing older version ($oldver)."
        $dir = versiondir $app $oldver $global
        try {
            rm -r -force -ea stop $dir
        } catch {
            error "Couldn't remove '$(friendly_path $dir)'; it may be in use."
            continue
        }
    }

    if(@(versions $app).length -eq 0) {
        $appdir = appdir $app $global
        try {
            # if last install failed, the directory seems to be locked and this
            # will throw an error about the directory not existing
            rm -r $appdir -ea stop -force
        } catch {
            if((test-path $appdir)) { throw } # only throw if the dir still exists
        }
    }

    # purge persistant data
    if ($purge) {
        $persist_dir = persistdir $app $global

        if (Test-Path $persist_dir) {
            try {
                rm -r $persist_dir -ea stop -force
            } catch {
                error "Couldn't remove '$(friendly_path $persist_dir)'; it may be in use."
                continue
            }
        }
    }

    success "'$app' was uninstalled."
}

exit 0
