# versions
function Get-LatestVersion {
    <#
    .SYNOPSIS
        Get latest version of app from manifest
    .PARAMETER AppName
        App's name
    .PARAMETER Bucket
        Bucket which the app belongs to
    .PARAMETER Uri
        Remote app manifest's URI
    #>
    [OutputType([String])]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [Alias('App')]
        [String]
        $AppName,
        [Parameter(Position = 1)]
        [String]
        $Bucket,
        [Parameter(Position = 2)]
        [String]
        $Uri
    )
    return (manifest $AppName $Bucket $Uri).version
}

function Select-CurrentVersion {
    <#
    .SYNOPSIS
        Select current version of installed app, from 'current\manifest.json' or modified time of version directory
    .PARAMETER AppName
        App's name
    .PARAMETER Global
        Globally installed application
    #>
    [OutputType([String])]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [Alias('App')]
        [String]
        $AppName,
        [Parameter(Position = 1)]
        [Switch]
        $Global
    )

    $appPath = appdir $AppName $Global
    if (Test-Path "$appPath\current") {
        $currentVersion = (installed_manifest $AppName 'current' $Global).version
    } else {
        $installedVersion = Get-InstalledVersion -AppName $AppName -Global:$Global
        if ($installedVersion) {
            $currentVersion = $installedVersion[-1]
        } else {
            $currentVersion = $null
        }
    }
    return $currentVersion
}

function Get-InstalledVersion {
    <#
    .SYNOPSIS
        Get all installed version of app, by checking version directories' 'install.json'
    .PARAMETER AppName
        App's name
    .PARAMETER Global
        Globally installed application
    .NOTES
        Versions are sorted from oldest to newest, i.e., latest installed version is the last one in the output array.
        If no installed version found, empty array will be returned.
    #>
    [OutputType([Object[]])]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [Alias('App')]
        [String]
        $AppName,
        [Parameter(Position = 1)]
        [Switch]
        $Global
    )

    $appPath = appdir $AppName $Global
    if (Test-Path $appPath) {
        return @((Get-ChildItem "$appPath\*\install.json" | Sort-Object -Property LastWriteTimeUtc).Directory.Name) -ne 'current'
    } else {
        return @()
    }

    # Deprecated
    # sort_versions (Get-ChildItem $appPath -dir -attr !reparsePoint | Where-Object { $null -ne $(Get-ChildItem $_.FullName) } | ForEach-Object { $_.Name })
}

function Compare-Version {
    <#
    .SYNOPSIS
        Compare versions, mainly according to SemVer's rules
    .PARAMETER ReferenceVersion
        Specifies a version used as a reference for comparison
    .PARAMETER DifferenceVersion
        Specifies the version that are compared to the reference version
    .PARAMETER Delimiter
        Specifies the delimiter of versions
    .OUTPUTS
        System.Int32
            '0' if DifferenceVersion is equal to ReferenceVersion,
            '1' if DifferenceVersion is greater then ReferenceVersion,
            '-1' if DifferenceVersion is less then ReferenceVersion
    #>
    [OutputType([Int])]
    [CmdletBinding()]
    param (
        [Parameter(Position = 0)]
        [String]
        $ReferenceVersion,
        [Parameter(Position = 1, ValueFromPipeline = $true)]
        [String]
        $DifferenceVersion,
        [String]
        $Delimiter = '-'
    )

    # Use '+' sign as post-release, see https://github.com/lukesampson/scoop/pull/3721#issuecomment-553718093
    $ReferenceVersion, $DifferenceVersion = @($ReferenceVersion, $DifferenceVersion) -replace '\+', '-'

    # Return 0 if versions are equal
    if ($DifferenceVersion -eq $ReferenceVersion) {
        return 0
    }

    # Preprocess versions (split, convert and separate)
    $splitReferenceVersion = @(SplitVersion -Version $ReferenceVersion -Delimiter $Delimiter)
    $splitDifferenceVersion = @(SplitVersion -Version $DifferenceVersion -Delimiter $Delimiter)

    # Nightly versions are always equal
    if ($splitReferenceVersion[0] -eq 'nightly' -and $splitDifferenceVersion[0] -eq 'nightly') {
        return 0
    }

    for ($i = 0; $i -lt [Math]::Max($splitReferenceVersion.Length, $splitDifferenceVersion.Length); $i++) {
        # '1.1-alpha' is less then '1.1'
        if ($i -ge $splitReferenceVersion.Length) {
            if ($splitDifferenceVersion[$i] -match 'alpha|beta|rc|pre') {
                return -1
            } else {
                return 1
            }
        }
        # '1.1' is greater then '1.1-beta'
        if ($i -ge $splitDifferenceVersion.Length) {
            if ($splitReferenceVersion[$i] -match 'alpha|beta|rc|pre') {
                return 1
            } else {
                return -1
            }
        }

        # If some parts of versions have '.', compare them with delimiter '.'
        if (($splitReferenceVersion[$i] -match '\.') -or ($splitDifferenceVersion[$i] -match '\.')) {
            $Result = Compare-Version -ReferenceVersion $splitReferenceVersion[$i] -DifferenceVersion $splitDifferenceVersion[$i] -Delimiter '.'
            # If the parts are equal, continue to next part, otherwise return
            if ($Result -ne 0) {
                return $Result
            } else {
                continue
            }
        }

        # Don't try to compare [Long] to [String]
        if ($null -ne $splitReferenceVersion[$i] -and $null -ne $splitDifferenceVersion[$i]) {
            if ($splitReferenceVersion[$i] -is [String] -and $splitDifferenceVersion[$i] -isnot [String]) {
                $splitDifferenceVersion[$i] = "$($splitDifferenceVersion[$i])"
            }
            if ($splitDifferenceVersion[$i] -is [String] -and $splitReferenceVersion[$i] -isnot [String]) {
                $splitReferenceVersion[$i] = "$($splitReferenceVersion[$i])"
            }
        }

        # Compare [String] or [Long]
        if ($splitDifferenceVersion[$i] -gt $splitReferenceVersion[$i]) {
            return 1
        }
        if ($splitDifferenceVersion[$i] -lt $splitReferenceVersion[$i]) {
            return -1
        }
    }
}

# Helper function
function SplitVersion {
    <#
    .SYNOPSIS
        Split version by Delimiter, convert number string to number, and separate letters from numbers
    .PARAMETER Version
        Specifies a version
    .PARAMETER Delimiter
        Specifies the delimiter of version (Literal)
    #>
    param (
        [String]
        $Version,
        [String]
        $Delimiter = '-'
    )
    $Version = $Version -replace '[a-zA-Z]+', "$Delimiter$&$Delimiter"
    return ($Version -split [Regex]::Escape($Delimiter) -ne '' | ForEach-Object { if ($_ -match '^\d+$') { [Long]$_ } else { $_ } })
}

# Deprecated
# Not used anymore in scoop core
function qsort($ary, $fn) {
    warn '"qsort" is deprecated. Please avoid using it anymore.'
    if($null -eq $ary) { return @() }
    if(!($ary -is [array])) { return @($ary) }

    $pivot = $ary[0]
    $rem = $ary[1..($ary.length-1)]

    $lesser = qsort ($rem | Where-Object { (& $fn $pivot $_) -lt 0 }) $fn

    $greater = qsort ($rem | Where-Object { (& $fn $pivot $_) -ge 0 }) $fn

    return @() + $lesser + @($pivot) + $greater
}

# Deprecated
# Not used anymore in scoop core
function sort_versions($versions) {
    warn '"sort_versions" is deprecated. Please avoid using it anymore.'
    qsort $versions Compare-Version
}

function compare_versions($a, $b) {
    Show-DeprecatedWarning $MyInvocation 'Compare-Version'
    # Please note the parameters' sequence
    return Compare-Version -ReferenceVersion $b -DifferenceVersion $a
}

function latest_version($app, $bucket, $url) {
    Show-DeprecatedWarning $MyInvocation 'Get-LatestVersion'
    return Get-LatestVersion -AppName $app -Bucket $bucket -Uri $url
}

function current_version($app, $global) {
    Show-DeprecatedWarning $MyInvocation 'Select-CurrentVersion'
    return Select-CurrentVersion -AppName $app -Global:$global
}

function versions($app, $global) {
    Show-DeprecatedWarning $MyInvocation 'Get-InstalledVersion'
    return Get-InstalledVersion -AppName $app -Global:$global
}
