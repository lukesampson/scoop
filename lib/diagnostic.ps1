<#
Diagnostic tests.
Return $true if the test passed, otherwise $false.
Use 'warn' to highlight the issue, and follow up with the recommended actions to rectify.
#>


function check_windows_defender ($global) {
  $defender = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
  if ($defender -and $defender.status) {
    if ($defender.status -eq [system.serviceprocess.servicecontrollerstatus]::running) {
      $hasGetMpPreference = Get-Command Get-MpPreference -ErrorAction SilentlyContinue
      if ($hasGetMpPreference) {
        $installPath = $scoopdir;
        if ($global) { $installPath = $globaldir; }

        $exclusionPath = (Get-MpPreference).exclusionPath
        if (!($exclusionPath -contains $installPath)) {
          warn "Windows Defender may slow down or disrupt installs with realtime scanning."
          Write-Host "  Consider running:"
          Write-Host "    sudo Add-MpPreference -ExclusionPath '$installPath'"
          Write-Host "  (Requires 'sudo' command. Run 'scoop install sudo' if you don't have it.)"
          return $false
        }
      }
    }
  }
  return $true
}
