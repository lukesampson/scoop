. "$psscriptroot\buckets.ps1"

if ($cmd -and $cmd.Contains('/')) {
    $bucket, $cmd = $cmd -split ('/');
    $bucketcmd = "$bucketsdir\$bucket\commands"
    $bucketcmd_exists = Test-Path $bucketcmd
}

function command_files {
    if ($bucket -and $bucketcmd_exists) {
        $files = gci ($bucketcmd)
    }
    else {
        $files = (gci (relpath '..\libexec')) + (gci "$scoopdir\shims")
    }

    $files | where { $_.name -match 'scoop-.*?\.ps1$' }
}

function commands {
    command_files | % { command_name $_ }
}

function command_name($filename) {
    $filename.name | sls 'scoop-(.*?)\.ps1$' | % { $_.matches[0].groups[1].value }
}

function command_path($cmd) {
    if ($bucketcmd_exists) {
        $cmd_path = "$bucketcmd\scoop-$cmd.ps1"
    }
    else {
        $cmd_path = relpath "..\libexec\scoop-$cmd.ps1"
    }

    # built in commands
    if (!(Test-Path $cmd_path)) {
        # get path from shim
        $shim_path = "$scoopdir\shims\scoop-$cmd.ps1"
        $line = ((gc $shim_path) | where { $_.startswith('$path') })
        if ($line) {
            iex -command "$line"
            $cmd_path = $path
        }
        else { $cmd_path = $shim_path }
    }

    $cmd_path
}

function exec($cmd, $arguments) {
    $cmd_path = command_path $cmd

    & $cmd_path @arguments
}
