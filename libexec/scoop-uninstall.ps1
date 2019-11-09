# Usage: scoop uninstall <app> [options]
# Summary: Uninstall an app
# Help: e.g. scoop uninstall git
#
# Options:
#   -g, --global   Uninstall a globally installed app
#   -p, --purge    Remove all persistent data

. "$PSScriptRoot\..\lib\core.ps1"
. "$PSScriptRoot\..\lib\manifest.ps1"
. "$PSScriptRoot\..\lib\help.ps1"
. "$PSScriptRoot\..\lib\install.ps1"
. "$PSScriptRoot\..\lib\shortcuts.ps1"
. "$PSScriptRoot\..\lib\psmodules.ps1"
. "$PSScriptRoot\..\lib\versions.ps1"
. "$PSScriptRoot\..\lib\getopt.ps1"

reset_aliases

# options
$opt, $apps, $err = getopt $args 'gp' 'global', 'purge'

if ($err) {
    error "scoop uninstall: $err"
    exit 1
}

$global = $opt.g -or $opt.global
$purge = $opt.p -or $opt.purge

if (!$apps) {
    error '<app> missing'
    my_usage
    exit 1
}

if ($global -and !(is_admin)) {
    error 'You need admin rights to uninstall global apps.'
    exit 1
}

if ($apps -eq 'scoop') {
    & "$PSScriptRoot\..\bin\uninstall.ps1" $global $purge
    exit
}

$apps = Confirm-InstallationStatus $apps -Global:$global
if (!$apps) { exit 0 }

:app_loop foreach ($_ in $apps) {
    ($app, $global) = $_

    $version = current_version $app $global
    Write-Host "Uninstalling '$app' ($version)."

    $dir = versiondir $app $version $global
    $persist_dir = persistdir $app $global

    #region Workaround for #2952
    $processdir = appdir $app $global | Resolve-Path | Select-Object -ExpandProperty Path
    if (Get-Process | Where-Object { $_.Path -like "$processdir\*" }) {
        error "Application is still running. Close all instances and try again."
        continue
    }
    #endregion Workaround for #2952

    try {
        Test-Path $dir -ErrorAction Stop | Out-Null
    } catch [UnauthorizedAccessException] {
        error "Access denied: $dir. You might need to restart."
        continue
    }

    $manifest = installed_manifest $app $version $global
    $install = install_info $app $version $global
    $architecture = $install.architecture

    run_uninstaller $manifest $architecture $dir
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
        # unlink all potential old link before doing recursive Remove-Item
        unlink_persist_data $dir
        Remove-Item $dir -Recurse -Force -ErrorAction Stop
    } catch {
        if (Test-Path $dir) {
            error "Couldn't remove '$(friendly_path $dir)'; it may be in use."
            continue
        }
    }

    # remove older versions
    $old = @(versions $app $global)
    foreach ($oldver in $old) {
        Write-Host "Removing older version ($oldver)."
        $dir = versiondir $app $oldver $global
        try {
            # unlink all potential old link before doing recursive Remove-Item
            unlink_persist_data $dir
            Remove-Item $dir -Recurse -Force -ErrorAction Stop
        } catch {
            error "Couldn't remove '$(friendly_path $dir)'; it may be in use."
            continue app_loop
        }
    }

    if (@(versions $app $global).length -eq 0) {
        $appdir = appdir $app $global
        try {
            # if last install failed, the directory seems to be locked and this
            # will throw an error about the directory not existing
            Remove-Item $appdir -Recurse -Force -ErrorAction Stop
        } catch {
            if ((Test-Path $appdir)) { throw } # only throw if the dir still exists
        }
    }

    # purge persistant data
    if ($purge) {
        Write-Host 'Removing persisted data.'
        $persist_dir = persistdir $app $global

        if (Test-Path $persist_dir) {
            try {
                Remove-Item $persist_dir -Recurse -Force -ErrorAction Stop
            } catch {
                error "Couldn't remove '$(friendly_path $persist_dir)'; it may be in use."
                continue
            }
        }
    }

    success "'$app' was uninstalled."
}

exit 0
