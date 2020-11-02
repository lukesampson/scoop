<#
.SYNOPSIS
    Uninstall ALL scoop applications and scoop itself.
.PARAMETER global
    Global applications will be uninstalled.
.PARAMETER purge
    Persisted data will be deleted.
#>
param(
    [bool] $global,
    [bool] $purge
)

. "$PSScriptRoot\..\lib\core.ps1"
. "$PSScriptRoot\..\lib\install.ps1"
. "$PSScriptRoot\..\lib\shortcuts.ps1"
. "$PSScriptRoot\..\lib\versions.ps1"
. "$PSScriptRoot\..\lib\manifest.ps1"

if ($global -and !(is_admin)) {
    error 'You need admin rights to uninstall globally.'
    exit 1
}

if ($purge) {
    warn 'This will uninstall Scoop, all the programs that have been installed with Scoop and all persisted data!'
} else {
    warn 'This will uninstall Scoop and all the programs that have been installed with Scoop!'
}

$code = Get-Random -Maximum 10000 -Minimum 1000
$yn = Read-Host "Are you sure? Input code ($($code)) to confirm"
if ($yn -ne $code) { exit }

$errors = $false

# Uninstall given app
function do_uninstall($app, $global) {
    $version = current_version $app $global
    $dir = versiondir $app $version $global
    $manifest = installed_manifest $app $version $global
    $install = install_info $app $version $global
    $architecture = $install.architecture

    Write-Output "Uninstalling '$app'"
    run_uninstaller $manifest $architecture $dir
    rm_shims $manifest $global $architecture

    # If a junction was used during install, that will have been used
    # as the reference directory. Othewise it will just be the version
    # directory.
    $refdir = unlink_current (appdir $app $global)

    env_rm_path $manifest $refdir $global
    env_rm $manifest $global

    $appdir = appdir $app $global
    try {
        Remove-Item $appdir -Recurse -Force -ErrorAction Stop
    } catch {
        $errors = $true
        warn "Couldn't remove $(friendly_path $appdir): $_.Exception"
    }
}

function rm_dir($dir) {
    try {
        Remove-Item $dir -Recurse -Force -ErrorAction Stop
    } catch {
        abort "Couldn't remove $(friendly_path $dir): $_"
    }
}

# Remove all folders (except persist) inside given scoop directory.
function keep_onlypersist($directory) {
    Get-ChildItem $directory -Exclude 'persist' | ForEach-Object { rm_dir $_ }
}

# Run uninstallation for each app if necessary, continuing if there's
# a problem deleting a directory (which is quite likely)
if ($global) {
    installed_apps $true | ForEach-Object { # global apps
        do_uninstall $_ $true
    }
}

installed_apps $false | ForEach-Object { # local apps
    do_uninstall $_ $false
}

if ($errors) {
    abort 'Not all apps could be deleted. Try again or restart.'
}

if ($purge) {
    rm_dir $scoopdir
    if ($global) { rm_dir $globaldir }
} else {
    keep_onlypersist $scoopdir
    if ($global) { keep_onlypersist $globaldir }
}

remove_from_path (shimdir $false)
if ($global) { remove_from_path (shimdir $true) }

success 'Scoop has been uninstalled.'
