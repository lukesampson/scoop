# Usage: scoop list [query]
# Summary: List installed apps
# Help: Lists all installed apps, or the apps matching the supplied query.
param($query)

. "$psscriptroot\..\lib\core.ps1"
. "$psscriptroot\..\lib\versions.ps1"
. "$psscriptroot\..\lib\manifest.ps1"
. "$psscriptroot\..\lib\buckets.ps1"

reset_aliases
$def_arch = default_architecture

$local = installed_apps $false | ForEach-Object { @{ name = $_ } }
$global = installed_apps $true | ForEach-Object { @{ name = $_; global = $true } }

$apps = @($local) + @($global)

if($apps) {
    write-host "Installed apps$(if($query) { `" matching '$query'`"}): `n"
    $apps | Sort-Object { $_.name } | Where-Object { !$query -or ($_.name -match $query) } | ForEach-Object {
        $app = $_.name
        $global = $_.global
        $ver = Select-CurrentVersion -AppName $app -Global:$global

        $install_info = install_info $app $ver $global
        write-host "  $app " -NoNewline
        write-host -f DarkCyan $ver -NoNewline

        if($global) { write-host -f DarkGreen ' *global*' -NoNewline }

        if (!$install_info) { Write-Host ' *failed*' -ForegroundColor DarkRed -NoNewline }
        if ($install_info.hold) { Write-Host ' *hold*' -ForegroundColor DarkMagenta -NoNewline }

        if ($install_info.bucket) {
            write-host -f Yellow " [$($install_info.bucket)]" -NoNewline
        } elseif ($install_info.url) {
            write-host -f Yellow " [$($install_info.url)]" -NoNewline
        }

        if ($install_info.architecture -and $def_arch -ne $install_info.architecture) {
            write-host -f DarkRed " {$($install_info.architecture)}" -NoNewline
        }
        write-host ''
    }
    write-host ''
    exit 0
} else {
    write-host "There aren't any apps installed."
    exit 1
}
