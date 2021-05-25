# Usage: scoop cat <app>
# Summary: Display the formula for an app
param($app)

. "$psscriptroot\..\lib\help.ps1"
. "$psscriptroot\..\lib\manifest.ps1"

reset_aliases

if(!$app) { my_usage; exit 1 }

if ($app -match '^(ht|f)tps?://|\\\\') {
    # check if $app is a URL or UNC path
    $url = $app
    $app = appname_from_url $url
    $manifest = url_manifest $url
    $manifest_file = $url
} else {
    # else $app is a normal app name
    $app, $bucket, $null = parse_app $app
    $manifest, $bucket = find_manifest $app $bucket
}

if (!$manifest) {
    abort "Could not find manifest for '$(show_app $app $bucket)'."
}

if (!$manifest_file) {
    $manifest_file = manifest_path $app $bucket
}

$data = Get-Content -Path $manifest_file

Write-Output $data

exit 0
