. "$psscriptroot\Scoop-TestLib.ps1"
. "$psscriptroot\..\lib\json.ps1"
. "$psscriptroot\..\lib\manifest.ps1"

Describe 'Pretty json formating' -Tag 'Scoop' {
    BeforeAll {
        $format = "$PSScriptRoot\fixtures\format"
        $manifests = Get-ChildItem "$format\formatted" -File -Filter '*.json'
    }

    Context 'Beautify manifest' {
        $manifests | ForEach-Object {
            if ($PSVersionTable.PSVersion.Major -gt 5) { $_ = $_.Name } # Fix for pwsh

            It "$_" {
                $pretty_json = (parse_json "$format\unformatted\$_") | ConvertToPrettyJson
                $correct = (Get-Content "$format\formatted\$_") -join "`r`n"
                $correct.CompareTo($pretty_json) | Should Be 0
            }
        }
    }
}
