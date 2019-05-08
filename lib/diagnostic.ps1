<#
Diagnostic tests.
Return $true if the test passed, otherwise $false.
Use 'warn' to highlight the issue, and follow up with the recommended actions to rectify.
#>

function check_windows_defender($global) {
    $defender = get-service -name WinDefend -errorAction SilentlyContinue
    if($defender -and $defender.status) {
        if($defender.status -eq [system.serviceprocess.servicecontrollerstatus]::running) {
            if (Test-CommandAvailable Get-MpPreference) {
                $installPath = $scoopdir;
                if($global) { $installPath = $globaldir; }

                $exclusionPath = (Get-MpPreference).exclusionPath
                if(!($exclusionPath -contains $installPath)) {
                    warn "Windows Defender may slow down or disrupt installs with realtime scanning."
                    write-host "  Consider running:"
                    write-host "    sudo Add-MpPreference -ExclusionPath '$installPath'"
                    write-host "  (Requires 'sudo' command. Run 'scoop install sudo' if you don't have it.)"
                    return $false
                }
            }
        }
    }
    return $true
}

function check_main_bucket {
    if ((Get-LocalBucket) -notcontains 'main'){
        warn 'Main bucket is not added.'
        Write-Host "  run 'scoop bucket add main'"

        return $false
    }

    return $true
}

function check_long_paths {
    $key = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -ErrorAction SilentlyContinue -Name 'LongPathsEnabled'
    if (!$key -or ($key.LongPathsEnabled -eq 0)) {
        warn 'LongPaths support is not enabled.'
        Write-Host "You can enable it with running:"
        Write-Host "    Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Value 1"

        return $false
    }

    return $true
}
