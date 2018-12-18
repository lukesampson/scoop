<#
.SYNOPSIS
    Format manifest.
.PARAMETER App
    Manifest to format.
    Wildcard is supported.
.PARAMETER Dir
    Where to search for manifest(s).
.EXAMPLE
    PS BUCKETROOT> .\bin\formatjson.ps1
    Format all manifests inside bucket directory.
.EXAMPLE
    PS BUCKETROOT> .\bin\formatjson.ps1 7zip
    Format manifest '7zip' inside bucket directory.
#>
# TODO: Notify all bucket maintainers about using format.ps1 instead of formatjson.ps1
param(
    [String] $App = '*',
    [ValidateScript( {
        if (!(Test-Path $_ -Type Container)) {
            throw "$_ is not a directory!"
        }
        $true
    })]
    [Alias('Path')]
    [String] $Dir = "$PSScriptRoot\..\bucket"
)

. "$PSScriptRoot\..\lib\core.ps1"
. "$PSScriptRoot\..\lib\manifest.ps1"
. "$PSScriptRoot\..\lib\json.ps1"

$Dir = Resolve-Path $Dir

Get-ChildItem $Dir "$App.json" | ForEach-Object {
    if ($PSVersionTable.PSVersion.Major -gt 5) { $_ = $_.Name } # Fix for pwsh

    # beautify
    $man = Scoop-ParseManifest "$Dir\$_" | ConvertToPrettyJson

    # convert to 4 spaces
    $man = $man -replace "`t", '    '
    Scoop-WriteManifest "$Dir\$_" $man
}
