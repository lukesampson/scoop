# requires -v 3

# remote install:
#   iex (iwr https://get.scoop.sh)
$old_erroractionpreference = $erroractionpreference
$erroractionpreference = 'stop' # quit if anything goes wrong

function KillScoopInstall() { 
    if ($ScoopInstallDontKill) { return }
    if ($ScoopInstallConfirmKill) {
        if ((Read-Host -prompt "Continue? [y/N]") -match "^[yY]") { # Continues on anything starting with "y" or "Y"
            Write-Output "Continuing..."
            return
        }
    }
    $erroractionpreference = $old_erroractionpreference
    Remove-Item -path Function:KillScoopInstall # Doesn't make sense to leave it hanging around...
    throw "A requirement failed and the install was stopped. Please review the output."
}

if(($PSVersionTable.PSVersion.Major) -lt 3) {
    Write-Host "PowerShell 3 or greater is required to run Scoop."
    Write-Host "Upgrade PowerShell: https://docs.microsoft.com/en-us/powershell/scripting/setup/installing-windows-powershell"
    KillScoopInstall
}

# show notification to change execution policy:
if((Get-ExecutionPolicy) -gt 'RemoteSigned' -and (Get-ExecutionPolicy) -ne 'Bypass') {
    Write-Host "PowerShell requires an execution policy of 'RemoteSigned' to run Scoop."
    Write-Host "To make this change please run:"
    Write-Host "'Set-ExecutionPolicy RemoteSigned -scope CurrentUser'"
    KillScoopInstall
}

if([System.Enum]::GetNames([System.Net.SecurityProtocolType]) -notcontains 'Tls12') {
    Write-Host "Scoop requires at least .NET Framework 4.5"
    Write-Host "Please download and install it first:"
    Write-Host "https://www.microsoft.com/net/download"
    KillScoopInstall
}

# get core functions
$core_url = 'https://raw.githubusercontent.com/lukesampson/scoop/master/lib/core.ps1'
Write-Output 'Initializing...'
Invoke-Expression (new-object net.webclient).downloadstring($core_url)

# prep
if(installed 'scoop') {
    Write-Host "Scoop is already installed. Please run 'scoop update' to get the latest version." -f red
    KillScoopInstall
}
$dir = ensure (versiondir 'scoop' 'current')

# download scoop zip
$zip_url = 'https://github.com/lukesampson/scoop/archive/master.zip'
$zip_file = "$dir\scoop.zip"
Write-Host 'Downloading...'
dl $zip_url $zip_file

'Extracting...'
Add-Type -Assembly "System.IO.Compression.FileSystem"
[IO.Compression.ZipFile]::ExtractToDirectory($zip_file,"$dir\_tmp")
Copy-Item "$dir\_tmp\scoop-master\*" $dir -r -force
Remove-Item "$dir\_tmp" -r -force
Remove-Item $zip_file

Write-Host 'Creating shim...'
shim "$dir\bin\scoop.ps1" $false

ensure_robocopy_in_path
ensure_scoop_in_path
scoop config lastupdate ([System.DateTime]::Now.ToString('o'))
success 'Scoop was installed successfully!'
Write-Host "Type 'scoop help' for instructions."

Remove-Item -path Function:KillScoopInstall # Doesn't make sense to leave it hanging around...
$erroractionpreference = $old_erroractionpreference # Reset $erroractionpreference to original value
