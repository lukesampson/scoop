# resolve dependencies for the supplied apps, and sort into the correct order
function install_order($apps, $arch) {
    $res = @()
    foreach ($app in $apps) {
        foreach ($dep in deps $app $arch) {
            if ($res -notcontains $dep) { $res += $dep}
        }
        if ($res -notcontains $app) { $res += $app }
    }
    return $res
}

# http://www.electricmonk.nl/docs/dependency_resolving_algorithm/dependency_resolving_algorithm.html
function deps($app, $arch) {
    $resolved = new-object collections.arraylist
    dep_resolve $app $arch $resolved @()

    if ($resolved.count -eq 1) { return @() } # no dependencies
    return $resolved[0..($resolved.count - 2)]
}

function dep_resolve($app, $arch, $resolved, $unresolved) {
    $app, $bucket, $null = parse_app $app
    $unresolved += $app
    $null, $manifest, $null, $null = Find-Manifest $app $bucket

    if(!$manifest) {
        if(((Get-LocalBucket) -notcontains $bucket) -and $bucket) {
            warn "Bucket '$bucket' not installed. Add it with 'scoop bucket add $bucket' or 'scoop bucket add $bucket <repo>'."
        }
        abort "Couldn't find manifest for '$app'$(if(!$bucket) { '.' } else { " from '$bucket' bucket." })"
    }

    $deps = @(install_deps $manifest $arch) + @(runtime_deps $manifest) | Select-Object -Unique

    foreach ($dep in $deps) {
        if ($resolved -notcontains $dep) {
            if ($unresolved -contains $dep) {
                abort "Circular dependency detected: '$app' -> '$dep'."
            }
            dep_resolve $dep $arch $resolved $unresolved
        }
    }
    $resolved.add($app) | Out-Null
    $unresolved = $unresolved -ne $app # remove from unresolved
}

function runtime_deps($manifest) {
    if ($manifest.depends) { return $manifest.depends }
}

function install_deps($manifest, $arch) {
    $deps = @()

    if (!(Test-7zipInstalled) -and (Test-7zipRequirement -URL (url $manifest $arch))) {
        $deps += '7zip'
    }
    if (!(Test-LessmsiInstalled) -and (Test-LessmsiRequirement -URL (url $manifest $arch))) {
        $deps += 'lessmsi'
    }
    if (!(Test-InnounpInstalled) -and $manifest.innosetup) {
        $deps += 'innounp'
    }

    return $deps
}
