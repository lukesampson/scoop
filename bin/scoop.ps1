#requires -v 3
param($cmd)

set-strictmode -off

. "$psscriptroot\..\lib\help.ps1"
. "$psscriptroot\..\lib\manifest.ps1"
. "$psscriptroot\..\lib\getopt.ps1"
. "$psscriptroot\..\lib\config.ps1"
. "$psscriptroot\..\lib\core.ps1"
. "$psscriptroot\..\lib\git.ps1"
. "$psscriptroot\..\lib\buckets.ps1"
. (relpath '..\lib\commands')

reset_aliases

# TODO: remove this in a few weeks
if ((Get-LocalBucket) -notcontains 'main') {
    warn "The main bucket of Scoop has been separated to 'https://github.com/ScoopInstaller/Main'"
    warn "You don't have the main bucket added, adding main bucket for you..."
    add_bucket 'main'
    exit
}

$commands = commands
if ('--version' -contains $cmd -or (!$cmd -and '-v' -contains $args)) {
    Push-Location $(versiondir 'scoop' 'current')
    write-host "Current Scoop version:"
    git_log --oneline HEAD -n 1
    write-host ""
    Pop-Location

    Get-LocalBucket | ForEach-Object {
        Push-Location (Find-BucketDirectory $_ -Root)
        if(test-path '.git') {
            write-host "'$_' bucket:"
            git_log --oneline HEAD -n 1
            write-host ""
        }
        Pop-Location
    }
}
elseif (@($null, '--help', '/?') -contains $cmd -or $args[0] -contains '-h') { exec 'help' $args }
elseif ($commands -contains $cmd) { exec $cmd $args }
else { "scoop: '$cmd' isn't a scoop command. See 'scoop help'."; exit 1 }
