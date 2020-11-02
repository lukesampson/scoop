# https://github.com/edymtt/nugetstandalone
$destinationFolder = "$PSScriptRoot\packages"
if (!(Test-Path -path $destinationFolder)) {
    Write-Host -f Red "Run .\install.ps1 first!"
    exit 1
}

nuget update packages.config -r $destinationFolder
Remove-Item $destinationFolder -Force -Recurse | Out-Null
nuget install packages.config -o $destinationFolder -ExcludeVersion
