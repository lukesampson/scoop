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

function script_deps($script) {
    $deps = @()
    if($script -is [Array]) {
        $script = $script -join "`n"
    }
    if([String]::IsNullOrEmpty($script)) {
        return $deps
    }

    if($script -like '*Expand-7zipArchive *' -or $script -like '*extract_7zip *') {
        $deps += '7zip'
    }
    if($script -like '*Expand-MsiArchive *' -or $script -like '*extract_msi *') {
        $deps += 'lessmsi'
    }
    if($script -like '*Expand-InnoArchive *' -or $script -like '*unpack_inno *') {
        if (get_config 'INNOSETUP_USE_INNOEXTRACT' $false) {
            $deps += 'innounp'
        } else {
            $deps += 'innoextract'
        }
    }
    if($script -like '*Expand-DarkArchive *') {
        $deps += 'dark'
    }

    return $deps
}

function install_deps($manifest, $arch) {
    $deps = @()

    if (!(Test-HelperInstalled -Helper 7zip) -and (Test-7zipRequirement -URL (url $manifest $arch))) {
        $deps += '7zip'
    }
    if (!(Test-HelperInstalled -Helper Lessmsi) -and (Test-LessmsiRequirement -URL (url $manifest $arch))) {
        $deps += 'lessmsi'
    }
    if ($manifest.innosetup) {
        if (get_config 'INNOSETUP_USE_INNOEXTRACT') {
            if (!(Test-HelperInstalled -Helper innoextract)) {
                $deps += 'innoextract'
            }
        } else {
            if (!(Test-HelperInstalled -Helper Innounp)) {
                $deps += 'innounp'
            }   
        }
    }

    $pre_install = arch_specific 'pre_install' $manifest $arch
    $installer = arch_specific 'installer' $manifest $arch
    $post_install = arch_specific 'post_install' $manifest $arch
    $deps += script_deps $pre_install
    $deps += script_deps $installer.script
    $deps += script_deps $post_install

    return $deps | Select-Object -Unique
}
