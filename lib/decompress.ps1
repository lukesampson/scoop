function Test-7zipRequirement {
    [CmdletBinding(DefaultParameterSetName = "Manifest")]
    [OutputType([Boolean])]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "Manifest")]
        [PSObject]
        $Manifest,
        [Parameter(Mandatory = $true, Position = 1, ParameterSetName = "Manifest")]
        [String]
        $Architecture,
        [Parameter(Mandatory = $true, ParameterSetName = "File")]
        [String]
        $File
    )
    if ($File) {
        return $File -match '\.((gz)|(tar)|(tgz)|(lzma)|(bz)|(bz2)|(7z)|(rar)|(iso)|(xz)|(lzh)|(nupkg))$'
    } else {
        $uri = url $Manifest $Architecture
        $installer = installer $Manifest $Architecture
        if (($installer.type -eq 'nsis')) {
            return $true
        } else {
            return ($uri | Where-Object { Test-7zipRequirement -File $_ }).Count -gt 0
        }
    }
}

function Test-LessmsiRequirement {
    [CmdletBinding()]
    [OutputType([Boolean])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [PSObject]
        $Manifest,
        [Parameter(Mandatory = $true, Position = 1)]
        [String]
        $Architecture
    )
    $uri = url $Manifest $Architecture
    if ((get_config MSIEXTRACT_USE_LESSMSI)) {
        return ($uri | Where-Object { $_ -match '\.msi$' }).Count -gt 0
    } else {
        return $false
    }
}

function Test-InnounpRequirement {
    [CmdletBinding()]
    [OutputType([Boolean])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [PSObject]
        $Manifest,
        [Parameter(Mandatory = $true, Position = 1)]
        [String]
        $Architecture
    )
    return (installer $Manifest $Architecture).type -eq 'inno'
}

function Test-DarkRequirement {
    [CmdletBinding()]
    [OutputType([Boolean])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [PSObject]
        $Manifest,
        [Parameter(Mandatory = $true, Position = 1)]
        [String]
        $Architecture
    )
    return (installer $Manifest $Architecture).type -eq 'wix'
}

function Expand-7zipArchive {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [String]
        $Path,
        [Parameter(Position = 1)]
        [String]
        $DestinationPath = (Split-Path $Path),
        [String]
        $ExtractDir,
        [Parameter(ValueFromRemainingArguments = $true)]
        [String]
        $Switches,
        [ValidateSet('All', 'Skip', 'Rename')]
        [String]
        $Overwrite,
        [Switch]
        $Removal
    )
    if ((get_config 7ZIPEXTRACT_USE_EXTERNAL)) {
        try {
            $7zPath = (Get-Command '7z' -CommandType Application | Select-Object -First 1).Source
        } catch [System.Management.Automation.CommandNotFoundException] {
            abort 'Cannot find external 7-Zip (7z.exe) while "7ZIPEXTRACT_USE_EXTERNAL" is "true"!`nRun "scoop config 7ZIPEXTRACT_USE_EXTERNAL false" or install 7-Zip manually and try again.'
        }
    } else {
        $7zPath = Get-HelperPath -Helper 7zip
    }
    $logPath = "$(Split-Path $Path)\7zip.log"
    $argList = @('x', "`"$Path`"", "-o`"$DestinationPath`"", '-y')
    $isTar = ((strip_ext $Path) -match '\.tar$') -or ($Path -match '\.t[abgpx]z2?$')
    if (!$isTar -and $ExtractDir) {
        $argList += "-ir!`"$ExtractDir\*`""
    }
    if ($Switches) {
        $argList += (-split $Switches)
    }
    switch ($Overwrite) {
        'All' { $argList += '-aoa' }
        'Skip' { $argList += '-aos' }
        'Rename' { $argList += '-aou' }
    }
    $status = Invoke-ExternalCommand $7zPath $argList -LogPath $logPath
    if (!$status) {
        abort "Failed to extract files from $Path.`nLog file:`n  $(friendly_path $logPath)`n$(new_issue_msg $app $bucket 'decompress error')"
    }
    if (!$isTar -and $ExtractDir) {
        movedir "$DestinationPath\$ExtractDir" $DestinationPath | Out-Null
    }
    if (Test-Path $logPath) {
        Remove-Item $logPath -Force
    }
    if ($isTar) {
        # Check for tar
        $status = Invoke-ExternalCommand $7zPath @('l', "`"$Path`"") -LogPath $logPath
        if ($status) {
            $tarFile = (Get-Content -Path $logPath)[-4] -replace '.{53}(.*)', '$1' # get inner tar file name
            Expand-7zipArchive -Path "$DestinationPath\$tarFile" -DestinationPath $DestinationPath -ExtractDir $ExtractDir -Removal
        } else {
            abort "Failed to list files in $Path.`nNot a 7-Zip supported archive file."
        }
    }
    if ($Removal) {
        # Remove original archive file
        Remove-Item $Path -Force
    }
}

function Expand-MsiArchive {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [String]
        $Path,
        [Parameter(Position = 1)]
        [String]
        $DestinationPath = (Split-Path $Path),
        [String]
        $ExtractDir,
        [Parameter(ValueFromRemainingArguments = $true)]
        [String]
        $Switches,
        [Switch]
        $Removal
    )
    $DestinationPath = $DestinationPath.TrimEnd('\')
    if ($ExtractDir) {
        $oriDestinationPath = $DestinationPath
        $DestinationPath = "$DestinationPath\_tmp"
    }
    if ((get_config MSIEXTRACT_USE_LESSMSI)) {
        $msiPath = Get-HelperPath -Helper Lessmsi
        $argList = @('x', "`"$Path`"", "`"$DestinationPath\\`"")
    } else {
        $msiPath = 'msiexec.exe'
        $argList = @('/a', "`"$Path`"", '/qn', "TARGETDIR=`"$DestinationPath\\SourceDir`"")
    }
    $logPath = "$(Split-Path $Path)\msi.log"
    if ($Switches) {
        $argList += (-split $Switches)
    }
    $status = Invoke-ExternalCommand $msiPath $argList -LogPath $logPath
    if (!$status) {
        abort "Failed to extract files from $Path.`nLog file:`n  $(friendly_path $logPath)`n$(new_issue_msg $app $bucket 'decompress error')"
    }
    if ($ExtractDir -and (Test-Path "$DestinationPath\SourceDir")) {
        movedir "$DestinationPath\SourceDir\$ExtractDir" $oriDestinationPath | Out-Null
        Remove-Directory -Path $DestinationPath
    } elseif ($ExtractDir) {
        movedir "$DestinationPath\$ExtractDir" $oriDestinationPath | Out-Null
        Remove-Directory -Path $DestinationPath
    } elseif (Test-Path "$DestinationPath\SourceDir") {
        movedir "$DestinationPath\SourceDir" $DestinationPath | Out-Null
    }
    if (($DestinationPath -ne (Split-Path $Path)) -and (Test-Path "$DestinationPath\$(fname $Path)")) {
        Remove-Item "$DestinationPath\$(fname $Path)" -Force
    }
    if (Test-Path $logPath) {
        Remove-Item $logPath -Force
    }
    if ($Removal) {
        # Remove original archive file
        Remove-Item $Path -Force
    }
}

function Expand-InnoArchive {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [String]
        $Path,
        [Parameter(Position = 1)]
        [String]
        $DestinationPath = (Split-Path $Path),
        [String]
        $ExtractDir,
        [Parameter(ValueFromRemainingArguments = $true)]
        [String]
        $Switches,
        [Switch]
        $Removal
    )
    $logPath = "$(Split-Path $Path)\innounp.log"
    $argList = @('-x', "-d`"$DestinationPath`"", "`"$Path`"", '-y')
    switch -Regex ($ExtractDir) {
        '^\.$' { break } # Suppress '-cDIR' param
        '^[^{].*' { $argList += "-c`"{app}\$ExtractDir`""; break }
        '^{.*' { $argList += "-c`"$ExtractDir`""; break }
        Default { $argList += '-c"{app}"' }
    }
    if ($Switches) {
        $argList += (-split $Switches)
    }
    $status = Invoke-ExternalCommand (Get-HelperPath -Helper Innounp) $argList -LogPath $logPath
    if (!$status) {
        abort "Failed to extract files from $Path.`nLog file:`n  $(friendly_path $logPath)`n$(new_issue_msg $app $bucket 'decompress error')"
    }
    if (Test-Path $logPath) {
        Remove-Item $logPath -Force
    }
    if ($Removal) {
        # Remove original archive file
        Remove-Item $Path -Force
    }
}

function Expand-ZipArchive {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [String]
        $Path,
        [Parameter(Position = 1)]
        [String]
        $DestinationPath = (Split-Path $Path),
        [String]
        $ExtractDir,
        [Switch]
        $Removal
    )
    if ($ExtractDir) {
        $oriDestinationPath = $DestinationPath
        $DestinationPath = "$DestinationPath\_tmp"
    }
    # Compatible with Pscx (https://github.com/Pscx/Pscx)
    Microsoft.PowerShell.Archive\Expand-Archive -Path $Path -DestinationPath $DestinationPath -Force
    if ($ExtractDir) {
        movedir "$DestinationPath\$ExtractDir" $oriDestinationPath | Out-Null
        Remove-Directory -Path $DestinationPath
    }
    if ($Removal) {
        # Remove original archive file
        Remove-Item $Path -Force
    }
}

function Expand-DarkArchive {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [String]
        $Path,
        [Parameter(Position = 1)]
        [String]
        $DestinationPath = (Split-Path $Path),
        [Parameter(ValueFromRemainingArguments = $true)]
        [String]
        $Switches,
        [Switch]
        $Removal
    )
    $logPath = "$(Split-Path $Path)\dark.log"
    $argList = @('-nologo', "-x `"$DestinationPath`"", "`"$Path`"")
    if ($Switches) {
        $argList += (-split $Switches)
    }
    $status = Invoke-ExternalCommand (Get-HelperPath -Helper Dark) $argList -LogPath $logPath
    if (!$status) {
        abort "Failed to extract files from $Path.`nLog file:`n  $(friendly_path $logPath)`n$(new_issue_msg $app $bucket 'decompress error')"
    }
    if (Test-Path $logPath) {
        Remove-Item $logPath -Force
    }
    if ($Removal) {
        # Remove original archive file
        Remove-Item $Path -Force
    }
}

function extract_7zip($path, $to, $removal) {
    Show-DeprecatedWarning $MyInvocation 'Expand-7zipArchive'
    Expand-7zipArchive -Path $path -DestinationPath $to -Removal:$removal @args
}

function extract_msi($path, $to, $removal) {
    Show-DeprecatedWarning $MyInvocation 'Expand-MsiArchive'
    Expand-MsiArchive -Path $path -DestinationPath $to -Removal:$removal @args
}

function unpack_inno($path, $to, $removal) {
    Show-DeprecatedWarning $MyInvocation 'Expand-InnoArchive'
    Expand-InnoArchive -Path $path -DestinationPath $to -Removal:$removal @args
}

function extract_zip($path, $to, $removal) {
    Show-DeprecatedWarning $MyInvocation 'Expand-ZipArchive'
    Expand-ZipArchive -Path $path -DestinationPath $to -Removal:$removal
}

function Expand-NsisInstaller {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [String]
        $Path,
        [Parameter(Position = 1)]
        [String]
        $DestinationPath = (Split-Path $Path),
        [String]
        $Architecture,
        [Switch]
        $Removal
    )
    Expand-7ZipArchive -Path $Path -DestinationPath $DestinationPath -Removal:$Removal
    if (Test-Path "$DestinationPath\`$PLUGINSDIR\app-64.7z") {
        if ($Architecture -eq '64bit') {
            Expand-7ZipArchive -Path "$DestinationPath\`$PLUGINSDIR\app-64.7z" -DestinationPath $DestinationPath
        } else {
            abort "Software doesn't support $Architecture architecture!"
        }
    } elseif (Test-Path "$DestinationPath\`$PLUGINSDIR\app-32.7z") {
        Expand-7ZipArchive -Path "$DestinationPath\`$PLUGINSDIR\app-32.7z" -DestinationPath $DestinationPath
    }
    @('*uninst*', '$*') | ForEach-Object { Get-Item "$DestinationPath\$_" | Remove-Item -Recurse -Force }
}

function Expand-WixInstaller {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [String]
        $Path,
        [Parameter(Position = 1)]
        [String]
        $DestinationPath = (Split-Path $Path),
        [String[]]
        $Exclude,
        [Switch]
        $Removal
    )
    Expand-DarkArchive -Path $Path -DestinationPath (ensure "$DestinationPath\_tmp") -Removal:$Removal
    if ($Exclude) {
        Remove-Item "$DestinationPath\_tmp\AttachedContainer\*.msi" -Include $Exclude -Force
    }
    Get-ChildItem "$DestinationPath\_tmp\AttachedContainer\*.msi" | ForEach-Object { Expand-MsiArchive $_ $DestinationPath }
    Remove-Directory -Path "$DestinationPath\_tmp"
}

function ConvertFrom-Inno {
    [CmdletBinding()]
    [OutputType([Hashtable])]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [Object[]]
        $InputObject,
        [String[]]
        $Include,
        [String[]]
        $Exclude
    )

    $fileList = New-Object System.Collections.Generic.List[System.Object]
    foreach ($file in ($InputObject -match '^Source:')) {
        if ($file -match 'Source: "(?<source>(?<srcdir>[^\\]*).*?)"; DestDir: "(?<destdir>.*?)"; (?:DestName: "(?<destname>.*?)"; )?(?:Components: (?<components>.*?);)?') {
            $fileList.Add([PSCustomObject]@{source = $Matches.source; srcdir = $Matches.srcdir; destdir = $Matches.destdir; destname = $Matches.destname; components = $Matches.components })
        }
    }
    if ($fileList.components) {
        $comps = $fileList.components | Select-Object -Unique
        $includeComps = @()
        $excludeComps = @()
        if ($Include) {
            $Include = $Include -split '\\' | Select-Object -Unique
            foreach ($incFile in $Include) {
                $incFile = '\b' + [Regex]::Escape($incFile) + '\b'
                $includeComps += $comps | Where-Object {
                    ($_ -match "$incFile") -and ($_ -notmatch "not[^(]*?\(?[^(]*?$incFile")
                }
                $excludeComps += $comps | Where-Object { $_ -match "not[^(]*?\(?[^(]*?$incFile" }
            }
        }
        if ($Exclude) {
            foreach ($excFile in $Exclude) {
                $excFile = '\b' + [Regex]::Escape($excFile) + '\b'
                $excludeComps += $comps | Where-Object { ($_ -match "$excFile") -and ($_ -notmatch "not[^(]*?\(?[^(]*?$excFile") -and ($_ -notmatch "or[^(]*?$excFile") -and ($_ -notmatch "$excFile[^(]*?or") }
            }
            $includeComps = $includeComps | Where-Object { $_ -notin $excludeComps }
        }
        $included = $fileList | Where-Object { $_.components -in $includeComps }
        $excluded = $fileList | Where-Object { $_.components -in $excludeComps }
    }

    return @{
        FileList = $fileList;
        Excluded = $excluded;
        Included = $included;
        Extracted = @($fileList.srcdir | Select-Object -Unique) -ne '{tmp}'
    }
}

function Expand-InnoInstaller {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [String]
        $Path,
        [Parameter(Position = 1)]
        [String]
        $DestinationPath = (Split-Path $Path),
        [String]
        $ExtractDir,
        [String[]]
        $Include,
        [String[]]
        $Exclude,
        [Switch]
        $Removal
    )
    if ($ExtractDir) {
        Expand-InnoArchive -Path $Path -DestinationPath $DestinationPath -ExtractDir $ExtractDir -Removal:$Removal
    } elseif ($Include -or $Exclude) {
        Expand-InnoArchive -Path $Path -DestinationPath $DestinationPath -ExtractDir '.' -Switches 'install_script.iss' # Just extract install script
        $installScript = Get-Content -Path "$DestinationPath\install_script.iss"
        $innoFiles = ConvertFrom-Inno -InputObject $installScript -Include $Include -Exclude ($Exclude -notlike '{*}')
        $innoFiles.Extracted | Where-Object { $_ -notin ($Exclude -like '{*}') } | ForEach-Object {
            Expand-InnoArchive -Path $Path -DestinationPath $DestinationPath -ExtractDir $_ -Switches '-a' -Removal:$Removal
        }
        if ($innoFiles.Excluded) {
            ($innoFiles.Excluded.source -replace '{.*?}', "$DestinationPath") | Remove-Item -Force -ErrorAction Ignore
        }
        if ($innoFiles.Included) {
            $innoFiles.Included | Where-Object { $_.source -match ',' } | Rename-Item -Path { $_.source -replace '{.*?}', "$DestinationPath" } -NewName { $_.destname } -Force -ErrorAction Ignore
        }
        Get-ChildItem -Path $DestinationPath -Filter '*,*' -Recurse | Rename-Item -NewName { $_.name -Replace ',\d', '' } -Force -ErrorAction Ignore
        Get-ChildItem -Path $DestinationPath -Filter '*,*' -Recurse | Remove-Item -Force -ErrorAction Ignore
        Remove-Directory -Path $DestinationPath -OnlyEmpty
        Remove-Item -Path "$DestinationPath\install_script.iss" -Force
    } else {
        Expand-InnoArchive -Path $Path -DestinationPath $DestinationPath -Removal:$Removal
    }
}
