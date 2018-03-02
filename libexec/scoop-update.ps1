# Usage: scoop update <app> [options]
# Summary: Update apps, or Scoop itself
# Help: 'scoop update' updates Scoop to the latest version.
# 'scoop update <app>' installs a new version of that app, if there is one.
#
# You can use '*' in place of <app> to update all apps.
#
# Options:
#   --global, -g       Update a globally installed app
#   --force, -f        Force update even when there isn't a newer version
#   --no-cache, -k     Don't use the download cache
#   --independent, -i  Don't install dependencies automatically
#   --quiet, -q        Hide extraneous messages
. "$psscriptroot\..\lib\core.ps1"
. "$psscriptroot\..\lib\shortcuts.ps1"
. "$psscriptroot\..\lib\psmodules.ps1"
. "$psscriptroot\..\lib\decompress.ps1"
. "$psscriptroot\..\lib\manifest.ps1"
. "$psscriptroot\..\lib\buckets.ps1"
. "$psscriptroot\..\lib\versions.ps1"
. "$psscriptroot\..\lib\getopt.ps1"
. "$psscriptroot\..\lib\depends.ps1"
. "$psscriptroot\..\lib\config.ps1"
. "$psscriptroot\..\lib\git.ps1"
. "$psscriptroot\..\lib\install.ps1"

reset_aliases

$opt, $apps, $err = getopt $args 'gfkqi' 'global','force', 'no-cache', 'quiet', 'independent'
if($err) { "scoop update: $err"; exit 1 }
$global = $opt.g -or $opt.global
$force = $opt.f -or $opt.force
$use_cache = !($opt.k -or $opt.'no-cache')
$quiet = $opt.q -or $opt.quiet
$independent = $opt.i -or $opt.independent

# load config
$repo = $(scoop config SCOOP_REPO)
if(!$repo) {
    $repo = "https://github.com/lukesampson/scoop"
    scoop config SCOOP_REPO "$repo"
}

$branch = $(scoop config SCOOP_BRANCH)
if(!$branch) {
    $branch = "master"
    scoop config SCOOP_BRANCH "$branch"
}

function update_scoop() {
    # check for git
    $git = try { gcm git -ea stop } catch { $null }
    if(!$git) { abort "Scoop uses Git to update itself. Run 'scoop install git' and try again." }

    write-host "Updating Scoop..."
    $currentdir = fullpath $(versiondir 'scoop' 'current')
    if(!(test-path "$currentdir\.git")) {
        $newdir = fullpath $(versiondir 'scoop' 'new')

        # get git scoop
        git_clone -q $repo --branch $branch --single-branch "`"$newdir`""

        # check if scoop was successful downloaded
        if(!(test-path "$newdir")) {
            abort 'Scoop update failed.'
        }

        # replace non-git scoop with the git version
        rm -r -force $currentdir -ea stop
        mv $newdir $currentdir
    }
    else {
        pushd $currentdir
        git_pull -q
        $res = $lastexitcode
        if($res -ne 0) {
            abort 'Update failed.'
        }
        popd
    }

    ensure_scoop_in_path
    shim "$currentdir\bin\scoop.ps1" $false

    @(buckets) | % {
        write-host "Updating '$_' bucket..."
        pushd (bucketdir $_)
        git_pull -q
        popd
    }

    scoop config lastupdate (get-date)
    success 'Scoop was updated successfully!'
}

function update($app, $global, $quiet = $false, $independent, $suggested, $use_cache = $true) {
    $old_version = current_version $app $global
    $old_manifest = installed_manifest $app $old_version $global
    $install = install_info $app $old_version $global
    $check_hash = $true

    # re-use architecture, bucket and url from first install
    $architecture = ensure_architecture $install.architecture
    $bucket = $install.bucket
    $url = $install.url

    if(!$independent) {
        # check dependencies
        $deps = @(deps $app $architecture) | ? { !(installed $_) }
        $deps | % { install_app $_ $architecture $global $suggested $use_cache }
    }

    $version = latest_version $app $bucket $url
    $is_nightly = $version -eq 'nightly'
    if($is_nightly) {
        $version = nightly_version $(get-date) $quiet
        $check_hash = $false
    }

    if(!$force -and ($old_version -eq $version)) {
        if (!$quiet) {
            warn "The latest version of '$app' ($version) is already installed."
        }
        return
    }
    if(!$version) {
        # installed from a custom bucket/no longer supported
        error "No manifest available for '$app'."
        return
    }

    $manifest = manifest $app $bucket $url

    write-host "Updating '$app' ($old_version -> $version)"

    $dir = versiondir $app $old_version $global

    write-host "Uninstalling '$app' ($old_version)"
    run_uninstaller $old_manifest $architecture $dir $bucket
    rm_shims $old_manifest $global $architecture
    env_rm_path $old_manifest $dir $global
    env_rm $old_manifest $global

    # If a junction was used during install, that will have been used
    # as the reference directory. Otherwise it will just be the version
    # directory.
    $refdir = unlink_current $dir

    if($bucket) {
        # add bucket name it was installed from
        $app = "$bucket/$app"
    }
    install_app $app $architecture $global $suggested $use_cache
}

if(!$apps) {
    if($global) {
        "scoop update: --global is invalid when <app> is not specified."; exit 1
    }
    if (!$use_cache) {
        "scoop update: --no-cache is invalid when <app> is not specified."; exit 1
    }
    update_scoop
} else {
    if($global -and !(is_admin)) {
        'ERROR: You need admin rights to update global apps.'; exit 1
    }

    if(is_scoop_outdated) {
        update_scoop
    }
    $outdated = @()
    $apps_param = $apps

    if($apps_param -eq '*') {
        $apps = applist (installed_apps $false) $false
        if($global) {
            $apps += applist (installed_apps $true) $true
        }
    } else {
        $apps = ensure_all_installed $apps_param $global
    }
    if($apps) {
        $apps | % {
            ($app, $global) = $_
            $status = app_status $app $global
            if($force -or $status.outdated) {
                $outdated += applist $app $global
                write-host -f yellow ("$app`: $($status.version) -> $($status.latest_version){0}" -f ('',' (global)')[$global])
            } elseif($apps_param -ne '*') {
                write-host -f green "$app`: $($status.version) (latest version)"
            }
        }

        if($outdated.Length -gt 1) { write-host -f DarkCyan "Updating $($outdated.Length) outdated apps:" }
        elseif($outdated.Length -eq 0) { write-host -f Green "Latest versions for all apps are installed! For more information try 'scoop status'" }
        else { write-host -f DarkCyan "Updating one outdated app:" }
    }

    $suggested = @{};
    # # $outdated is a list of ($app, $global) tuples
    $outdated | % { update @_ $quiet $independent $suggested $use_cache }
}

exit 0
