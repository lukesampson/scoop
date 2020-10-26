# Usage: scoop search <query>
# Summary: Search available apps
# Help: Searches for apps that are available to install.
#
# If used with [query], shows app names that match the query.
# Without [query], shows all the available apps.
param(
    [Parameter(Mandatory = $true)]
    $Query,
    [Switch] $Remote
)
. "$psscriptroot\..\lib\manifest.ps1"
. "$psscriptroot\..\lib\install.ps1"
. "$psscriptroot\..\lib\versions.ps1"

reset_aliases

function search_bucket($bucket, $query) {
    $arch = default_architecture
    $apps = apps_in_bucket (Find-BucketDirectory $bucket) | ForEach-Object {
        $manifest = manifest $_ $bucket
        @{
            name = $_
            version = $manifest.version
            description = $manifest.description
            shortcuts = @(arch_specific 'shortcuts' $manifest $arch)
            matchingShortcuts = @()
            bin = @(arch_specific 'bin' $manifest $arch)
            matchingBinaries = @()
        }
    }

    if(!$query) {
        return $apps
    }

    try {
        $query = New-Object Regex $query, 'IgnoreCase'
    } catch {
        abort "Invalid regular expression: $($_.exception.innerexception.message)"
    }

    $result = @()

    foreach ($app in $apps) {
        if($app.name -match $query -and !$result.Contains($app)) {
            $result += $app
        }

        $app.bin | ForEach-Object {
            $exe, $name, $arg = shim_def $_
            if($name -match $query) {
                $bin = @{'exe' = $exe; 'name' = $name }
                if($result.Contains($app)) {
                    $result[$result.IndexOf($app)].matchingBinaries += $bin
                } else {
                    $app.matchingBinaries += $bin
                    $result += $app
                }
            }
        }

        foreach ($shortcut in $app.shortcuts) {
            if($shortcut -is [Array] -and $shortcut.length -ge 2) {
                $name = $shortcut[1]
                if($name -match $query) {
                    if($result.Contains($app)) {
                        $result[$result.IndexOf($app)].matchingShortcuts += $name
                    } else {
                        $app.matchingShortcuts += $name
                        $result += $app
                    }
                }
            }
        }
    }

    return $result
}

function github_ratelimit_reached {
    return (Invoke-RestMethod -Uri 'https://api.github.com/rate_limit').rate.remaining -eq 0
}

$ratelimit_reached = github_ratelimit_reached

function search_remote($bucket, $query) {
    $repo = known_bucket_repo $bucket
    if($ratelimit_reached) {
        Write-Host "GitHub ratelimit reached: Can't query $repo"
        return $null
    }

    $uri = [system.uri]($repo)
    if ($uri.absolutepath -match '/([a-zA-Z0-9]*)/([a-zA-Z0-9-]*)(.git|/)?') {
        $user = $matches[1]
        $repo_name = $matches[2]
        $request_uri = "https://api.github.com/repos/$user/$repo_name/git/trees/HEAD?recursive=1"
        try {
            if((Get-Command Invoke-RestMethod).parameters.ContainsKey('ResponseHeadersVariable')) {
                $response = Invoke-RestMethod -Uri $request_uri -ResponseHeadersVariable headers
                if($headers['X-RateLimit-Remaining']) {
                    $ratelimit_reached = (1 -eq $headers['X-RateLimit-Remaining'][0])
                }
            } else {
                $response = Invoke-RestMethod -Uri $request_uri
                $ratelimit_reached = github_ratelimit_reached
            }

            $result = $response.tree | Where-Object {
                $_.path -match "(^(.*$query.*).json$)"
            } | ForEach-Object { $matches[2] }
        } catch [System.Web.Http.HttpResponseException] {
            $ratelimit_reached = $true
        }
    }

    return $result
}

function search_remotes($query) {
    $results = known_buckets | Where-Object { !(test-path $(Find-BucketDirectory $_)) } | ForEach-Object {
        @{bucket = $_; results = (search_remote $_ $query)}
    } | Where-Object { $_.results }

    return $results
}

Write-Host 'Searching in local buckets ...'
$local_results = @()

foreach ($bucket in (Get-LocalBucket) {
    $result = search_bucket $bucket $query
    if(!$result) {
        return
    }
    $local_results += $result
    $result | ForEach-Object {

        Write-Host "$bucket" -NoNewline -ForegroundColor Yellow
        Write-Host '/' -NoNewline
        Write-Host $_.name -ForegroundColor Green
        Write-Host "  Version: " -NoNewline
        Write-Host $_.version -ForegroundColor DarkCyan
        if($_.description) {
            Write-Host "  Description: $($_.description)"
        }
        if($_.matchingBinaries) {
            Write-Host "  Binaries:"
            $_.matchingBinaries | ForEach-Object {
                if($_.exe.Contains($_.name)) {
                    Write-Host "    - $($_.exe)"
                } else {
                    Write-Host "    - $($_.exe) > $($_.name)"
                }
            }
        }
        if($_.matchingShortcuts) {
            Write-Host "  Shortcuts:"
            $_.matchingShortcuts | ForEach-Object {
                Write-Host "    - $_"
            }
        }
    }
}

if(!$local_results) {
    error 'No matches in local buckets found.'
}

if(!$local_results -or $Remote) {
    if(!$ratelimit_reached) {
        Write-Host 'Searching in remote buckets ...'
        $remote_results = search_remotes $query
        if ($remote_results) {
            Write-Host "`nResults from other known buckets:`n"
            $remote_results | ForEach-Object {
                Write-Host "'$($_.bucket)' bucket (Run 'scoop bucket add $($_.bucket)'):"
                $_.results | ForEach-Object { "    $_" }
            }
        } else {
            error 'No matches in remote buckets found.'
        }
    } else {
        error "GitHub ratelimit reached: Can't query known repositories, please try again later"
    }
}

exit 0
