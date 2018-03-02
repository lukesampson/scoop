param($global)

. "$psscriptroot\..\lib\core.ps1"
. "$psscriptroot\..\lib\install.ps1"
. "$psscriptroot\..\lib\shortcuts.ps1"
. "$psscriptroot\..\lib\versions.ps1"
. "$psscriptroot\..\lib\manifest.ps1"

if($global -and !(is_admin)) {
    "ERROR: You need admin rights to uninstall globally."; exit 1
}

warn 'This will uninstall Scoop and all the programs that have been installed with Scoop!'
$yn = read-host 'Are you sure? (yN)'
if($yn -notlike 'y*') { exit }

$errors = $false
function do_uninstall($app, $global) {
    $version = current_version $app $global
    $dir = versiondir $app $version $global
    $manifest = installed_manifest $app $version $global
    $install = install_info $app $version $global
    $architecture = $install.architecture

    echo "Uninstalling '$app'"
    run_uninstaller $manifest $architecture $dir $install.bucket
    rm_shims $manifest $global $architecture

    # If a junction was used during install, that will have been used
    # as the reference directory. Othewise it will just be the version
    # directory.
    $refdir = unlink_current (appdir $app $global)

    env_rm_path $manifest $refdir $global
    env_rm $manifest $global

    $appdir = appdir $app $global
    try {
        rm -r -force $appdir -ea stop
    } catch {
        $errors = $true
        warn "Couldn't remove $(friendly_path $appdir): $_.exception"
    }
}
function rm_dir($dir) {
    try {
        rm -r -force $dir -ea stop
    } catch {
        abort "Couldn't remove $(friendly_path $dir): $_"
    }
}

# run uninstallation for each app if necessary, continuing if there's
# a problem deleting a directory (which is quite likely)
if($global) {
    installed_apps $true | % { # global apps
        do_uninstall $_ $true
    }
}
installed_apps $false | % { # local apps
    do_uninstall $_ $false
}

if($errors) {
    abort "Not all apps could be deleted. Try again or restart."
}

rm_dir $scoopdir
if($global) { rm_dir $globaldir }

remove_from_path (shimdir $false)
if($global) { remove_from_path (shimdir $true) }

success "Scoop has been uninstalled."
