<#
.SYNOPSIS
    Check if ALL urls inside manifest have correct hashes.
.PARAMETER App
    Manifest to be checked.
    Wildcard is supported.
.PARAMETER Dir
    Where to search for manifest(s).
.PARAMETER Update
    When there are mismatched hashes, manifest will be updated.
.PARAMETER ForceUpdate
    Manifest will be updated all the time. Not only when there are mismatched hashes.
.PARAMETER SkipCorrect
    Manifests without mismatch will not be shown.
.PARAMETER UseCache
    Downloaded files will not be deleted after script finish.
    Should not be used, because check should be used for downloading actual version of file (as normal user, not finding in some document from vendors, which could be damaged / wrong (Example: Slack@3.3.1 lukesampson/scoop-extras#1192)), not some previously downloaded.
.EXAMPLE
    PS BUCKETROOT> .\bin\checkhashes.ps1
    Check all manifests for hash mismatch.
.EXAMPLE
    PS BUCKETROOT> .\bin\checkhashes.ps1 MANIFEST -Update
    Check MANIFEST and Update if there are some wrong hashes.
#>
param(
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
    [Switch] $Update,
    [Switch] $ForceUpdate,
    [Switch] $SkipCorrect,
    [Alias('k')]
    [Switch] $UseCache
)

. "$PSScriptRoot\..\lib\core.ps1"
. "$PSScriptRoot\..\lib\manifest.ps1"
. "$PSScriptRoot\..\lib\buckets.ps1"
. "$PSScriptRoot\..\lib\autoupdate.ps1"
. "$PSScriptRoot\..\lib\json.ps1"
. "$PSScriptRoot\..\lib\versions.ps1"
. "$PSScriptRoot\..\lib\install.ps1"
. "$PSScriptRoot\..\lib\unix.ps1"

$Dir = Resolve-Path $Dir
if ($ForceUpdate) { $Update = $true }
# Cleanup
if (!$UseCache) { Remove-Item "$cachedir\*HASH_CHECK*" -Force }

function err ([String] $name, [String[]] $message) {
    Write-Host "$name`: " -ForegroundColor Red -NoNewline
    Write-Host ($message -join "`r`n") -ForegroundColor Red
}

$MANIFESTS = @()
foreach ($single in Get-ChildItem $Dir "$App.json") {
    $name = (strip_ext $single.Name)
    $manifest = parse_json "$Dir\$($single.Name)"

    # Skip nighly manifests, since their hash validation is skipped
    if ($manifest.version -eq 'nightly') { continue }

    $urls = @()
    $hashes = @()

    if ($manifest.url) {
        $manifest.url | ForEach-Object { $urls += $_ }
        $manifest.hash | ForEach-Object { $hashes += $_ }
    } elseif ($manifest.architecture) {
        # First handle 64bit
        url $manifest '64bit' | ForEach-Object { $urls += $_ }
        hash $manifest '64bit' | ForEach-Object { $hashes += $_ }
        url $manifest '32bit' | ForEach-Object { $urls += $_ }
        hash $manifest '32bit' | ForEach-Object { $hashes += $_ }
    } else {
        err $name 'Manifest does not contain URL property.'
        continue
    }

    # Number of URLS and Hashes is different
    if ($urls.Length -ne $hashes.Length) {
        err $name 'URLS and hashes count mismatch.'
        continue
    }

    $MANIFESTS += @{
        app      = $name
        manifest = $manifest
        urls     = $urls
        hashes   = $hashes
    }
}

# clear any existing events
Get-Event | ForEach-Object { Remove-Event $_.SourceIdentifier }

foreach ($current in $MANIFESTS) {
    $count = 0
    # Array of indexes mismatched hashes.
    $mismatched = @()
    # Array of computed hashes
    $actuals = @()

    $current.urls | ForEach-Object {
        $algorithm, $expected = get_hash $current.hashes[$count]
        $version = 'HASH_CHECK'
        $tmp = $expected_hash -split ':'

        dl_with_cache $current.app $version $_ $null $null -use_cache:$UseCache

        $to_check = cache_path $current.app $version $_
        $actual_hash = compute_hash $to_check $algorithm

        # Append type of algorithm to both expected and actual if it's not sha256
        if ($algorithm -ne 'sha256') {
            $actual_hash = "$algorithm`:$actual_hash"
            $expected = "$algorithm`:$expected"
        }

        $actuals += $actual_hash
        if ($actual_hash -ne $expected) {
            $mismatched += $count
        }
        $count++
    }

    if ($mismatched.Length -eq 0 ) {
        if (!$SkipCorrect) {
            Write-Host "$($current.app): " -NoNewline
            Write-Host 'OK' -ForegroundColor Green
        }
    } else {
        Write-Host "$($current.app): " -NoNewline
        Write-Host 'Mismatch found ' -ForegroundColor Red
        $mismatched | ForEach-Object {
            $file = cache_path $current.app $version $current.urls[$_]
            Write-Host  "`tURL:`t`t$($current.urls[$_])"
            if (Test-Path $file) {
                Write-Host  "`tFirst bytes:`t$((get_magic_bytes_pretty $file ' ').ToUpper())"
            }
            Write-Host  "`tExpected:`t$($current.hashes[$_])" -ForegroundColor Green
            Write-Host  "`tActual:`t`t$($actuals[$_])" -ForegroundColor Red
        }
    }

    if ($Update) {
        if ($current.manifest.url -and $current.manifest.hash) {
            $current.manifest.hash = $actuals
        } else {
            $platforms = ($current.manifest.architecture | Get-Member -MemberType NoteProperty).Name
            # Defaults to zero, don't know, which architecture is available
            $64bit_count = 0
            $32bit_count = 0

            if ($platforms.Contains('64bit')) {
                $64bit_count = $current.manifest.architecture.'64bit'.hash.Count
                # 64bit is get, donwloaded and added first
                $current.manifest.architecture.'64bit'.hash = $actuals[0..($64bit_count - 1)]
            }
            if ($platforms.Contains('32bit')) {
                $32bit_count = $current.manifest.architecture.'32bit'.hash.Count
                $max = $64bit_count + $32bit_count - 1 # Edge case if manifest contains 64bit and 32bit.
                $current.manifest.architecture.'32bit'.hash = $actuals[($64bit_count)..$max]
            }
        }

        Write-Host "Writing updated $($current.app) manifest" -ForegroundColor DarkGreen

        $current.manifest = $current.manifest | ConvertToPrettyJson
        $path = Resolve-Path "$Dir\$($current.app).json"
        [System.IO.File]::WriteAllLines($path, $current.manifest)
    }
}
