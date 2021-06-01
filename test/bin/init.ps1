Write-Host "PowerShell: $($PSVersionTable.PSVersion)"
(7z.exe | Select-String -Pattern '7-Zip').ToString()
Write-Host "Install dependencies ..."
Install-Module -Repository PSGallery -Scope CurrentUser -Force -Name Pester -RequiredVersion 4.10.1 -SkipPublisherCheck
Install-Module -Repository PSGallery -Scope CurrentUser -Force -Name PSScriptAnalyzer,BuildHelpers

if ($env:CI_WINDOWS -eq $true) {
    # Do not force maintainers to have this inside environment appveyor config
    if (-not $env:SCOOP_HELPERS) {
        $env:SCOOP_HELPERS = 'C:\projects\helpers'
        [System.Environment]::SetEnvironmentVariable('SCOOP_HELPERS', $env:SCOOP_HELPERS, 'Machine')
    }

    if(!(Test-Path $env:SCOOP_HELPERS)) {
        New-Item -ItemType Directory -Path $env:SCOOP_HELPERS
    }
    if(!(Test-Path "$env:SCOOP_HELPERS\lessmsi\lessmsi.exe")) {
        Start-FileDownload 'https://github.com/activescott/lessmsi/releases/download/v1.6.3/lessmsi-v1.6.3.zip' -FileName "$env:SCOOP_HELPERS\lessmsi.zip"
        & 7z.exe x "$env:SCOOP_HELPERS\lessmsi.zip" -o"$env:SCOOP_HELPERS\lessmsi" -y
    }
    if(!(Test-Path "$env:SCOOP_HELPERS\innounp\innounp.exe")) {
        Start-FileDownload 'https://raw.githubusercontent.com/ScoopInstaller/Binary/master/innounp/innounp048.rar' -FileName "$env:SCOOP_HELPERS\innounp.rar"
        & 7z.exe x "$env:SCOOP_HELPERS\innounp.rar" -o"$env:SCOOP_HELPERS\innounp" -y
    }
    if(!(Test-Path "$env:SCOOP_HELPERS\zstd\zstd.exe")) {
        Start-FileDownload 'https://github.com/facebook/zstd/releases/download/v1.5.0/zstd-v1.5.0-win64.zip' -FileName "$env:SCOOP_HELPERS\zstd.zip"
        & 7z.exe x "$env:SCOOP_HELPERS\zstd.zip" "zstd-v1.5.0-win64" -o"$env:SCOOP_HELPERS\zstd" -y
    }
}

if($env:CI -eq $true) {
    Write-Host "Load 'BuildHelpers' environment variables ..."
    Set-BuildEnvironment -Force
}

$buildVariables = ( Get-ChildItem -Path 'Env:' ).Where( { $_.Name -match "^(?:BH|CI(?:_|$)|APPVEYOR)" } )
$buildVariables += ( Get-Variable -Name 'CI_*' -Scope 'Script' )
$details = $buildVariables |
    Where-Object -FilterScript { $_.Name -notmatch 'EMAIL' } |
    Sort-Object -Property 'Name' |
    Format-Table -AutoSize -Property 'Name', 'Value' |
    Out-String
Write-Host "CI variables:"
Write-Host $details -ForegroundColor DarkGray
