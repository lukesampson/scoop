# Usage: scoop status
# Summary: Show status and check for new app versions

. "$psscriptroot\..\lib\core.ps1"
. "$psscriptroot\..\lib\manifest.ps1"
. "$psscriptroot\..\lib\buckets.ps1"
. "$psscriptroot\..\lib\versions.ps1"
. "$psscriptroot\..\lib\depends.ps1"
. "$psscriptroot\..\lib\git.ps1"

reset_aliases

function Test-IsGitRepositoryBehind($location) {
    Push-Location $location
    git_fetch -q origin
    $is_behind = (git_status) -like '*is behind*' -as [bool]
    Pop-Location

    return $is_behind
}

function Test-IsScoopBehind {
    $currentdir = fullpath (versiondir 'scoop' 'current')
    if (!(Test-Path "$currentdir\.git") -or (Test-IsGitRepositoryBehind $currentdir)) {
        return $true
    }

    foreach ($bucket in Get-LocalBucket) {
        $loc = Find-BucketDirectory $bucket -Root
        if (Test-IsGitRepositoryBehind $loc) {
            return $true
        }
    }

    return $false
}

# check if scoop needs updating
$needs_update = Test-IsScoopBehind
if ($needs_update) {
    warn "Scoop is out of date. Run 'scoop update' to get the latest changes."
}
else { success "Scoop is up to date." }

$failed = @()
$outdated = @()
$removed = @()
$missing_deps = @()
$onhold = @()

$true, $false | ForEach-Object { # local and global apps
    $global = $_
    $dir = appsdir $global
    if(!(test-path $dir)) { return }

    Get-ChildItem $dir | Where-Object name -ne 'scoop' | ForEach-Object {
        $app = $_.name
        $status = app_status $app $global
        if($status.failed) {
            $failed += @{ $app = $status.version }
        }
        if($status.removed) {
            $removed += @{ $app = $status.version }
        }
        if($status.outdated) {
            $outdated += @{ $app = @($status.version, $status.latest_version) }
            if($status.hold) {
                $onhold += @{ $app = @($status.version, $status.latest_version) }
            }
        }
        if($status.missing_deps) {
            $missing_deps += ,(@($app) + @($status.missing_deps))
        }
    }
}

if($outdated) {
    write-host -f DarkCyan 'Updates are available for:'
    $outdated.keys | ForEach-Object {
        $versions = $outdated.$_
        "    $_`: $($versions[0]) -> $($versions[1])"
    }
}

if($onhold) {
    write-host -f DarkCyan 'These apps are outdated and on hold:'
    $onhold.keys | ForEach-Object {
        $versions = $onhold.$_
        "    $_`: $($versions[0]) -> $($versions[1])"
    }
}

if($removed) {
    write-host -f DarkCyan 'These app manifests have been removed:'
    $removed.keys | ForEach-Object {
        "    $_"
    }
}

if($failed) {
    write-host -f DarkCyan 'These apps failed to install:'
    $failed.keys | ForEach-Object {
        "    $_"
    }
}

if($missing_deps) {
    write-host -f DarkCyan 'Missing runtime dependencies:'
    $missing_deps | ForEach-Object {
        $app, $deps = $_
        "    '$app' requires '$([string]::join("', '", $deps))'"
    }
}

if(!$old -and !$removed -and !$failed -and !$missing_deps -and !$needs_update) {
    success "Everything is ok!"
}

exit 0
