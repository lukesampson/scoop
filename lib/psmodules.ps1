$modulesdir = "$scoopdir\modules"

function install_psmodule($manifest, $dir, $global) {
    $psmodule = $manifest.psmodule
    if(!$psmodule) { return }

    if($global) {
        abort "Installing PowerShell modules globally is not implemented!"
    }

    $modulesdir = ensure $modulesdir
    ensure_in_psmodulepath $modulesdir $global

    $module_name = $psmodule.name
    if(!$module_name) {
        abort "Invalid manifest: The 'name' property is missing from 'psmodule'."
    }

    $linkfrom = "$modulesdir\$module_name"
    write-host "Installing PowerShell module '$module_name'"

    write-host "Linking $(friendly_path $linkfrom) => $(friendly_path $dir)"

    if(test-path $linkfrom) {
        warn "$(friendly_path $linkfrom) already exists. It will be replaced."
        & "$env:COMSPEC" /c "rmdir `"$linkfrom`""
    }

    & "$env:COMSPEC" /c "mklink /d `"$linkfrom`" `"$dir`"" | out-null
}

function uninstall_psmodule($manifest, $dir, $global) {
    $psmodule = $manifest.psmodule
    if(!$psmodule) { return }

    $module_name = $psmodule.name
    write-host "Uninstalling PowerShell module '$module_name'."

    $linkfrom = "$modulesdir\$module_name"
    if(test-path $linkfrom) {
        write-host "Removing $(friendly_path $linkfrom)"
        $linkfrom = resolve-path $linkfrom
        & "$env:COMSPEC" /c "rmdir `"$linkfrom`""
    }
}

function ensure_in_psmodulepath($dir, $global) {
    $path = env 'psmodulepath' $global
    if(!$global -and $null -eq $path) {
        $path = "$env:USERPROFILE\Documents\WindowsPowerShell\Modules"
    }
    $dir = fullpath $dir
    if($path -notmatch [regex]::escape($dir)) {
        write-output "Adding $(friendly_path $dir) to $(if($global){'global'}else{'your'}) PowerShell module path."

        env 'psmodulepath' $global "$dir;$path" # for future sessions...
        $env:psmodulepath = "$dir;$env:psmodulepath" # for this session
    }
}
