# Usage: scoop checkup
# Summary: Check for potential problems
# Help: Performs a series of diagnostic tests to try to identify things that may
# cause problems with Scoop.

. "$psscriptroot\..\lib\diagnostic.ps1"

$issues = 0

$issues += !(check_windows_defender $false)
$issues += !(check_windows_defender $true)
$issues += !(check_main_bucket)
$issues += !(check_long_paths)

$globaldir = New-Object System.IO.DriveInfo($globaldir)
if($globaldir.DriveFormat -ne 'NTFS') {
    error "Scoop requires an NTFS volume to work! Please point `$env:SCOOP_GLOBAL variable to another Drive."
    $issues++
}

$scoopdir = New-Object System.IO.DriveInfo($scoopdir)
if($scoopdir.DriveFormat -ne 'NTFS') {
    error "Scoop requires an NTFS volume to work! Please point `$env:SCOOP variable to another Drive."
    $issues++
}

if($issues) {
    warn "Found $issues potential $(pluralize $issues problem problems)."
} else {
    success "No problems identified!"
}

exit 0
