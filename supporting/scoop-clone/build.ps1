Param([Switch]$Fast)
Push-Location $PSScriptRoot
. "$PSScriptRoot\..\..\lib\install.ps1"

if(!$Fast) {
    Write-Host "Install dependencies ..."
    Invoke-Expression "$PSScriptRoot\install.ps1"
}

$output = "$PSScriptRoot\bin"

Write-Output 'Gathering libraries ...'
Copy-Item "$PSScriptRoot\packages\LibGit2Sharp\lib\net46\LibGit2Sharp.dll" "$output"

New-Item -ItemType Directory -Path "$output\lib\win32\x64\" -ErrorAction SilentlyContinue | Out-Null
Copy-Item "$PSScriptRoot\packages\LibGit2Sharp.NativeBinaries\runtimes\win-x64\native\git2-*.dll" "$output\lib\win32\x64\"

New-Item -ItemType Directory -Path "$output\lib\win32\x86\" -ErrorAction SilentlyContinue | Out-Null
Copy-Item "$PSScriptRoot\packages\LibGit2Sharp.NativeBinaries\runtimes\win-x86\native\git2-*.dll" "$output\lib\win32\x86\"

Write-Output 'Computing checksums ...'
Remove-Item "$PSScriptRoot\bin\checksum.sha256" -ErrorAction Ignore
Remove-Item "$PSScriptRoot\bin\checksum.sha512" -ErrorAction Ignore
Get-ChildItem "$PSScriptRoot\bin\*" -Include *.ps1,*.dll -Recurse | ForEach-Object {
    "$(compute_hash $_ 'sha256') *$($_.FullName.Replace($output, '').TrimStart('\'))" | Out-File "$PSScriptRoot\bin\checksum.sha256" -Append -Encoding oem
    "$(compute_hash $_ 'sha512') *$($_.FullName.Replace($output, '').TrimStart('\'))" | Out-File "$PSScriptRoot\bin\checksum.sha512" -Append -Encoding oem
}
Pop-Location
