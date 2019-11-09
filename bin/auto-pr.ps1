<#
.SYNOPSIS
    Updates manifests and pushes them or creates pull-requests.
.DESCRIPTION
    Updates manifests and pushes them directly to the master branch or creates pull-requests for upstream.
.PARAMETER Upstream
    Upstream repository with the target branch.
    Must be in format '<user>/<repo>:<branch>'
.PARAMETER App
    Manifest name to search.
    Placeholders are supported.
.PARAMETER Dir
    The directory where to search for manifests.
.PARAMETER Push
    Push updates directly to 'origin master'.
.PARAMETER Request
    Create pull-requests on 'upstream master' for each update.
.PARAMETER Help
    Print help to console.
.PARAMETER SpecialSnowflakes
    An array of manifests, which should be updated all the time. (-ForceUpdate parameter to checkver)
.PARAMETER SkipUpdated
    Updated manifests will not be shown.
.EXAMPLE
    PS BUCKETROOT > .\bin\auto-pr.ps1 'someUsername/repository:branch' -Request
.EXAMPLE
    PS BUCKETROOT > .\bin\auto-pr.ps1 -Push
    Update all manifests inside 'bucket/' directory.
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateScript( {
        if (!($_ -match '^(.*)\/(.*):(.*)$')) {
            throw 'Upstream must be in this format: <user>/<repo>:<branch>'
        }
        $true
    })]
    [String] $Upstream,
    [String] $App = '*',
    [Parameter(Mandatory = $true)]
    [ValidateScript( {
        if (!(Test-Path $_ -Type Container)) {
            throw "$_ is not a directory!"
        } else {
            $true
        }
    })]
    [String] $Dir,
    [Switch] $Push,
    [Switch] $Request,
    [Switch] $Help,
    [string[]] $SpecialSnowflakes,
    [Switch] $SkipUpdated
)

. "$PSScriptRoot\..\lib\manifest.ps1"
. "$PSScriptRoot\..\lib\json.ps1"
. "$PSScriptRoot\..\lib\unix.ps1"

$Dir = Resolve-Path $Dir

if ((!$Push -and !$Request) -or $Help) {
    Write-Host @'
Usage: auto-pr.ps1 [OPTION]

Mandatory options:
  -p,  -push                       push updates directly to 'origin master'
  -r,  -request                    create pull-requests on 'upstream master' for each update

Optional options:
  -u,  -upstream                   upstream repository with target branch
                                   only used if -r is set (default: lukesampson/scoop:master)
  -h,  -help
'@
    exit 0
}

if (is_unix) {
    if (!(which hub)) {
        Write-Host "Please install hub ('brew install hub' or visit: https://hub.github.com/)" -ForegroundColor Yellow
        exit 1
    }
} else {
    if (!(scoop which hub)) {
        Write-Host "Please install hub 'scoop install hub'" -ForegroundColor Yellow
        exit 1
    }
}

function execute($cmd) {
    Write-Host $cmd -ForegroundColor Green
    $output = Invoke-Expression $cmd

    if ($LASTEXITCODE -gt 0) {
        abort "^^^ Error! See above ^^^ (last command: $cmd)"
    }

    return $output
}

function pull_requests($json, [String] $app, [String] $upstream, [String] $manifest) {
    $version = $json.version
    $homepage = $json.homepage
    $branch = "manifest/$app-$version"

    execute 'hub checkout master'
    Write-Host "hub rev-parse --verify $branch" -ForegroundColor Green
    hub rev-parse --verify $branch

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Skipping update $app ($version) ..." -ForegroundColor Yellow
        return
    }

    Write-Host "Creating update $app ($version) ..." -ForegroundColor DarkCyan
    execute "hub checkout -b $branch"
    execute "hub add $manifest"
    execute "hub commit -m '${app}: Update to version $version'"
    Write-Host "Pushing update $app ($version) ..." -ForegroundColor DarkCyan
    execute "hub push origin $branch"

    if ($LASTEXITCODE -gt 0) {
        error "Push failed! (hub push origin $branch)"
        execute 'hub reset'
        return
    }

    Start-Sleep 1
    Write-Host "Pull-Request update $app ($version) ..." -ForegroundColor DarkCyan
    Write-Host "hub pull-request -m '<msg>' -b '$upstream' -h '$branch'" -ForegroundColor Green

    $msg = @"
$app`: Update to version $version

Hello lovely humans,
a new version of [$app]($homepage) is available.

| State       | Update :rocket: |
| :---------- | :-------------- |
| New version | $version        |
"@

    hub pull-request -m "$msg" -b '$upstream' -h '$branch'
    if ($LASTEXITCODE -gt 0) {
        execute 'hub reset'
        abort "Pull Request failed! (hub pull-request -m '${app}: Update to version $version' -b '$upstream' -h '$branch')"
    }
}

Write-Host 'Updating ...' -ForegroundColor DarkCyan
if ($Push) {
    execute 'hub pull origin master'
    execute 'hub checkout master'
} else {
    execute 'hub pull upstream master'
    execute 'hub push origin master'
}

. "$PSScriptRoot\checkver.ps1" -App $App -Dir $Dir -Update -SkipUpdated:$SkipUpdated
if ($SpecialSnowflakes) {
    Write-Host "Forcing update on our special snowflakes: $($SpecialSnowflakes -join ',')" -ForegroundColor DarkCyan
    $SpecialSnowflakes -split ',' | ForEach-Object {
        . "$PSScriptRoot\checkver.ps1" $_ -Dir $Dir -ForceUpdate
    }
}

hub diff --name-only | ForEach-Object {
    $manifest = $_
    if (!$manifest.EndsWith('.json')) {
        return
    }

    $app = ([System.IO.Path]::GetFileNameWithoutExtension($manifest))
    $json = parse_json $manifest
    if (!$json.version) {
        error "Invalid manifest: $manifest ..."
        return
    }
    $version = $json.version

    if ($Push) {
        Write-Host "Creating update $app ($version) ..." -ForegroundColor DarkCyan
        execute "hub add $manifest"

        # detect if file was staged, because it's not when only LF or CRLF have changed
        $status = execute 'hub status --porcelain -uno'
        $status = $status | Where-Object { $_ -match "M\s{2}.*$app.json" }
        if ($status -and $status.StartsWith('M  ') -and $status.EndsWith("$app.json")) {
            execute "hub commit -m '${app}: Update to version $version'"
        } else {
            Write-Host "Skipping $app because only LF/CRLF changes were detected ..." -ForegroundColor Yellow
        }
    } else {
        pull_requests $json $app $Upstream $manifest
    }
}

if ($Push) {
    Write-Host 'Pushing updates ...' -ForegroundColor DarkCyan
    execute 'hub push origin master'
} else {
    Write-Host 'Returning to master branch and removing unstaged files ...' -ForegroundColor DarkCyan
    execute 'hub checkout -f master'
}

execute 'hub reset --hard'
