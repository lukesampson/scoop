# Usage: scoop update <app> [options]
# Summary: Update apps, or Scoop itself
# Help: 'scoop update' updates Scoop to the latest version.
# 'scoop update <app>' installs a new version of that app, if there is one.
#
# You can use '*' in place of <app> to update all apps.
#
# Options:
#   -f, --force               Force update even when there isn't a newer version
#   -g, --global              Update a globally installed app
#   -i, --independent         Don't install dependencies automatically
#   -k, --no-cache            Don't use the download cache
#   -s, --skip                Skip hash validation (use with caution!)
#   -q, --quiet               Hide extraneous messages

. "$psscriptroot\..\lib\core.ps1"
. "$psscriptroot\..\lib\shortcuts.ps1"
. "$psscriptroot\..\lib\psmodules.ps1"
. "$psscriptroot\..\lib\decompress.ps1"
. "$psscriptroot\..\lib\manifest.ps1"
. "$psscriptroot\..\lib\buckets.ps1"
. "$psscriptroot\..\lib\versions.ps1"
. "$psscriptroot\..\lib\getopt.ps1"
. "$psscriptroot\..\lib\depends.ps1"
. "$psscriptroot\..\lib\git.ps1"
. "$psscriptroot\..\lib\install.ps1"

reset_aliases

$opt, $apps, $err = getopt $args 'gfiksq' 'global', 'force', 'independent', 'no-cache', 'skip', 'quiet'
if ($err) { "scoop update: $err"; exit 1 }
$global = $opt.g -or $opt.global
$force = $opt.f -or $opt.force
$check_hash = !($opt.s -or $opt.skip)
$use_cache = !($opt.k -or $opt.'no-cache')
$quiet = $opt.q -or $opt.quiet
$independent = $opt.i -or $opt.independent

# load config
$configRepo = get_config SCOOP_REPO
if (!$configRepo) {
    $configRepo = "https://github.com/lukesampson/scoop"
    set_config SCOOP_REPO $configRepo | Out-Null
}

# Find current update channel from config
$configBranch = get_config SCOOP_BRANCH
if (!$configBranch) {
    $configBranch = "master"
    set_config SCOOP_BRANCH $configBranch | Out-Null
}

if(($PSVersionTable.PSVersion.Major) -lt 5) {
    # check powershell version
    Write-Output "PowerShell 5 or later is required to run Scoop."
    Write-Output "Upgrade PowerShell: https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-core-on-windows"
    break
}

function update_scoop() {
    # check for git
    if(!(Test-CommandAvailable git)) { abort "Scoop uses Git to update itself. Run 'scoop install git' and try again." }

    write-host "Updating Scoop..."
    $last_update = $(last_scoop_update)
    if ($null -eq $last_update) {$last_update = [System.DateTime]::Now}
    $last_update = $last_update.ToString('s')
    $show_update_log = get_config 'show_update_log' $true
    $currentdir = fullpath $(versiondir 'scoop' 'current')
    if (!(test-path "$currentdir\.git")) {
        $newdir = fullpath $(versiondir 'scoop' 'new')

        # get git scoop
        git_clone -q $configRepo --branch $configBranch --single-branch "`"$newdir`""

        # check if scoop was successful downloaded
        if (!(test-path "$newdir")) {
            abort 'Scoop update failed.'
        }

        # replace non-git scoop with the git version
        Remove-Item -r -force $currentdir -ea stop
        Move-Item $newdir $currentdir
    } else {
        Push-Location $currentdir

        $previousCommit = Invoke-Expression 'git rev-parse HEAD'
        $currentRepo = Invoke-Expression "git config remote.origin.url"
        $currentBranch = Invoke-Expression "git branch"

        $isRepoChanged = !($currentRepo -match $configRepo)
        $isBranchChanged = !($currentBranch -match "\*\s+$configBranch")

        # Change remote url if the repo is changed
        if ($isRepoChanged) {
            Invoke-Expression "git config remote.origin.url '$configRepo'"
        }

        # Fetch and reset local repo if the repo or the branch is changed
        if ($isRepoChanged -or $isBranchChanged) {
            # Reset git fetch refs, so that it can fetch all branches (GH-3368)
            Invoke-Expression "git config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'"
            # fetch remote branch
            git_fetch --force origin "refs/heads/`"$configBranch`":refs/remotes/origin/$configBranch" -q
            # checkout and track the branch
            git_checkout -B $configBranch -t origin/$configBranch -q
            # reset branch HEAD
            Invoke-Expression "git reset --hard origin/$configBranch -q"
        } else {
            git_pull -q
        }

        $res = $lastexitcode
        if ($show_update_log) {
            Invoke-Expression "git --no-pager log --no-decorate --format='tformat: * %C(yellow)%h%Creset %<|(72,trunc)%s %C(cyan)%cr%Creset' '$previousCommit..HEAD'"
        }

        Pop-Location
        if ($res -ne 0) {
            abort 'Update failed.'
        }
    }

    if ((Get-LocalBucket) -notcontains 'main') {
        info "The main bucket of Scoop has been separated to 'https://github.com/ScoopInstaller/Main'"
        info "Adding main bucket..."
        add_bucket 'main'
    }

    ensure_scoop_in_path
    shim "$currentdir\bin\scoop.ps1" $false

    Get-LocalBucket | ForEach-Object {
        write-host "Updating '$_' bucket..."

        $loc = Find-BucketDirectory $_ -Root
        # Make sure main bucket, which was downloaded as zip, will be properly "converted" into git
        if (($_ -eq 'main') -and !(Test-Path "$loc\.git")) {
            rm_bucket 'main'
            add_bucket 'main'
        }

        Push-Location $loc
        $previousCommit = (Invoke-Expression 'git rev-parse HEAD')
        git_pull -q
        if ($show_update_log) {
            Invoke-Expression "git --no-pager log --no-decorate --format='tformat: * %C(yellow)%h%Creset %<|(72,trunc)%s %C(cyan)%cr%Creset' '$previousCommit..HEAD'"
        }
        Pop-Location
    }

    set_config lastupdate ([System.DateTime]::Now.ToString('o')) | Out-Null
    success 'Scoop was updated successfully!'
}

function update($app, $global, $quiet = $false, $independent, $suggested, $use_cache = $true, $check_hash = $true) {
    $old_version = current_version $app $global
    $old_manifest = installed_manifest $app $old_version $global
    $install = install_info $app $old_version $global

    # re-use architecture, bucket and url from first install
    $architecture = ensure_architecture $install.architecture
    $bucket = $install.bucket
    if ($null -eq $bucket) {
        $bucket = 'main'
    }
    $url = $install.url

    if (!$independent) {
        # check dependencies
        $man = if ($url) { $url } else { $app }
        $deps = @(deps $man $architecture) | Where-Object { !(installed $_) }
        $deps | ForEach-Object { install_app $_ $architecture $global $suggested $use_cache $check_hash }
    }

    $version = latest_version $app $bucket $url
    $is_nightly = $version -eq 'nightly'
    if ($is_nightly) {
        $version = nightly_version $(get-date) $quiet
        $check_hash = $false
    }

    if (!$force -and ($old_version -eq $version)) {
        if (!$quiet) {
            warn "The latest version of '$app' ($version) is already installed."
        }
        return
    }
    if (!$version) {
        # installed from a custom bucket/no longer supported
        error "No manifest available for '$app'."
        return
    }

    $manifest = manifest $app $bucket $url

    write-host "Updating '$app' ($old_version -> $version)"

    # region Workaround
    # Workaround for https://github.com/lukesampson/scoop/issues/2220 until install is refactored
    # Remove and replace whole region after proper fix
    Write-Host "Downloading new version"
    if (Test-Aria2Enabled) {
        dl_with_cache_aria2 $app $version $manifest $architecture $cachedir $manifest.cookie $true $check_hash
    } else {
        $urls = url $manifest $architecture

        foreach ($url in $urls) {
            dl_with_cache $app $version $url $null $manifest.cookie $true

            if ($check_hash) {
                $manifest_hash = hash_for_url $manifest $url $architecture
                $source = fullpath (cache_path $app $version $url)
                $ok, $err = check_hash $source $manifest_hash $(show_app $app $bucket)

                if (!$ok) {
                    error $err
                    if (test-path $source) {
                        # rm cached file
                        Remove-Item -force $source
                    }
                    if ($url.Contains('sourceforge.net')) {
                        Write-Host -f yellow 'SourceForge.net is known for causing hash validation fails. Please try again before opening a ticket.'
                    }
                    abort $(new_issue_msg $app $bucket "hash check failed")
                }
            }
        }
    }
    # There is no need to check hash again while installing
    $check_hash = $false
    # endregion Workaround

    $dir = versiondir $app $old_version $global
    $persist_dir = persistdir $app $global

    #region Workaround for #2952
    $processdir = appdir $app $global | Resolve-Path | Select-Object -ExpandProperty Path
    if (Get-Process | Where-Object { $_.Path -like "$processdir\*" }) {
        error "Application is still running. Close all instances and try again."
        return
    }
    #endregion Workaround for #2952

    write-host "Uninstalling '$app' ($old_version)"
    run_uninstaller $old_manifest $architecture $dir
    rm_shims $old_manifest $global $architecture
    env_rm_path $old_manifest $dir $global
    env_rm $old_manifest $global

    # If a junction was used during install, that will have been used
    # as the reference directory. Otherwise it will just be the version
    # directory.
    $refdir = unlink_current $dir

    if ($force -and ($old_version -eq $version)) {
        if (!(Test-Path "$dir/../_$version.old")) {
            Move-Item "$dir" "$dir/../_$version.old"
        } else {
            $i = 1
            While (Test-Path "$dir/../_$version.old($i)") {
                $i++
            }
            Move-Item "$dir" "$dir/../_$version.old($i)"
        }
    }

    if ($bucket) {
        # add bucket name it was installed from
        $app = "$bucket/$app"
    }
    if ($install.url) {
        # use the url of the install json if the application was installed through url
        $app = $install.url
    }
    install_app $app $architecture $global $suggested $use_cache $check_hash
}

if (!$apps) {
    if ($global) {
        "scoop update: --global is invalid when <app> is not specified."; exit 1
    }
    if (!$use_cache) {
        "scoop update: --no-cache is invalid when <app> is not specified."; exit 1
    }
    update_scoop
} else {
    if ($global -and !(is_admin)) {
        'ERROR: You need admin rights to update global apps.'; exit 1
    }

    if (is_scoop_outdated) {
        update_scoop
    }
    $outdated = @()
    $apps_param = $apps

    if ($apps_param -eq '*') {
        $apps = applist (installed_apps $false) $false
        if ($global) {
            $apps += applist (installed_apps $true) $true
        }
    } else {
        $apps = Confirm-InstallationStatus $apps_param -Global:$global
    }
    if ($apps) {
        $apps | ForEach-Object {
            ($app, $global) = $_
            $status = app_status $app $global
            if ($force -or $status.outdated) {
                if(!$status.hold) {
                    $outdated += applist $app $global
                    write-host -f yellow ("$app`: $($status.version) -> $($status.latest_version){0}" -f ('',' (global)')[$global])
                } else {
                    warn "'$app' is held to version $($status.version)"
                }
            } elseif ($apps_param -ne '*') {
                write-host -f green "$app`: $($status.version) (latest version)"
            }
        }

        if ($outdated -and (Test-Aria2Enabled)) {
            warn "Scoop uses 'aria2c' for multi-connection downloads."
            warn "Should it cause issues, run 'scoop config aria2-enabled false' to disable it."
        }
        if ($outdated.Length -gt 1) {
            write-host -f DarkCyan "Updating $($outdated.Length) outdated apps:"
        } elseif ($outdated.Length -eq 0) {
            write-host -f Green "Latest versions for all apps are installed! For more information try 'scoop status'"
        } else {
            write-host -f DarkCyan "Updating one outdated app:"
        }
    }

    $suggested = @{};
    # $outdated is a list of ($app, $global) tuples
    $outdated | ForEach-Object { update @_ $quiet $independent $suggested $use_cache $check_hash }
}

exit 0
