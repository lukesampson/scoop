<#
.SYNOPSIS
    Check manifest for a newer version.
.DESCRIPTION
    Checks websites for newer versions using an (optional) regular expression defined in the manifest.
.PARAMETER App
    Manifest name to search.
    Placeholders are supported.
.PARAMETER Dir
    Where to search for manifest(s).
.PARAMETER Update
    Update given manifest
.PARAMETER ForceUpdate
    Update given manifest(s) even when there is no new version.
    Useful for hash updates.
.PARAMETER SkipUpdated
    Updated manifests will not be shown.
.EXAMPLE
    PS BUCKETROOT > .\bin\checkver.ps1
    Check all manifest inside default directory.
.EXAMPLE
    PS BUCKETROOT > .\bin\checkver.ps1 -SkipUpdated
    Check all manifest inside default directory (list only outdated manifests).
.EXAMPLE
    PS BUCKETROOT > .\bin\checkver.ps1 -Update
    Check all manifests and update All outdated manifests.
.EXAMPLE
    PS BUCKETROOT > .\bin\checkver.ps1 APP
    Check manifest APP.json inside default directory.
.EXAMPLE
    PS BUCKETROOT > .\bin\checkver.ps1 APP -Update
    Check manifest APP.json and update, if there is newer version.
.EXAMPLE
    PS BUCKETROOT > .\bin\checkver.ps1 APP -ForceUpdate
    Check manifest APP.json and update, even if there is no new version.
.EXAMPLE
    PS BUCKETROOT > .\bin\checkver.ps1 APP -Update -Version VER
    Check manifest APP.json and update, using version VER
.EXAMPLE
    PS BUCKETROOT > .\bin\checkver.ps1 APP DIR
    Check manifest APP.json inside ./DIR directory.
.EXAMPLE
    PS BUCKETROOT > .\bin\checkver.ps1 -Dir DIR
    Check all manifests inside ./DIR directory.
.EXAMPLE
    PS BUCKETROOT > .\bin\checkver.ps1 APP DIR -Update
    Check manifest APP.json inside ./DIR directory and update if there is newer version.
#>
param(
    [String] $App = '*',
    [Parameter(Mandatory = $true)]
    [ValidateScript( {
        if (!(Test-Path $_ -Type Container)) {
            throw "$_ is not a directory!"
        } else {
            $true
        }
    })]
    [String] $Dir,
    [Switch] $Update,
    [Switch] $ForceUpdate,
    [Switch] $SkipUpdated,
    [String] $Version = ''
)

. "$psscriptroot\..\lib\core.ps1"
. "$psscriptroot\..\lib\manifest.ps1"
. "$psscriptroot\..\lib\buckets.ps1"
. "$psscriptroot\..\lib\autoupdate.ps1"
. "$psscriptroot\..\lib\json.ps1"
. "$psscriptroot\..\lib\versions.ps1"
. "$psscriptroot\..\lib\install.ps1" # needed for hash generation
. "$psscriptroot\..\lib\unix.ps1"

$Dir = Resolve-Path $Dir
$Search = $App

# get apps to check
$Queue = @()
$json = ''
Get-ChildItem $Dir "$App.json" | ForEach-Object {
    $json = parse_json "$Dir\$($_.Name)"
    if ($json.checkver) {
        $Queue += , @($_.Name, $json)
    }
}

# clear any existing events
Get-Event | ForEach-Object {
    Remove-Event $_.SourceIdentifier
}

$LastModifiedFile = "$cachedir\lastmodified.json"
$GitHubToken = $env:SCOOP_CHECKVER_TOKEN, (get_config 'checkverToken') | Where-Object { -not [String]::IsNullOrEmpty($_) } | Select-Object -First 1

# start all downloads
$Queue | ForEach-Object {
    $name, $json = $_

    $substitutions = get_version_substitutions $json.version

    $wc = New-Object Net.Webclient
    if ($json.checkver.useragent) {
        $wc.Headers.Add('User-Agent', (substitute $json.checkver.useragent $substitutions))
    } else {
        $wc.Headers.Add('User-Agent', (Get-UserAgent))
    }
    Register-ObjectEvent $wc downloadstringcompleted -ErrorAction Stop | Out-Null

    $githubRegex = '\/releases\/tag\/(?:v|V)?([\d.]+)'

    $url = $json.homepage
    if ($json.checkver.url) {
        $url = $json.checkver.url
    }
    $regex = ''
    $jsonpath = ''
    $xpath = ''
    $replace = ''

    if(!(Test-Path $LastModifiedFile)) {
        @{} | ConvertTo-Json | Set-Content $LastModifiedFile
    }
    $modified = Get-Content $LastModifiedFile | ConvertFrom-Json
    if($modified.$app) {
        $wc.Headers.Add('If-Modified-Since', $modified.$app)
    }
    if($GitHubToken) {
        $wc.Headers.Add('Authorization', "token $GitHubToken")
    }

    if ($json.checkver -eq 'github') {
        if (!$json.homepage.StartsWith('https://github.com/')) {
            error "$name checkver expects the homepage to be a github repository"
        }
        $url = $json.homepage + '/releases/latest'
        $url = $url -replace 'https://github.com/','https://api.github.com/repos/'
        $regex = $githubRegex
    }

    if ($json.checkver.github) {
        $url = $json.checkver.github + '/releases/latest'
        $url = $url -replace 'https://github.com/','https://api.github.com/repos/'
        $regex = $githubRegex
    }

    if ($json.checkver.re) {
        $regex = $json.checkver.re
    }
    if ($json.checkver.regex) {
        $regex = $json.checkver.regex
    }

    if ($json.checkver.jp) {
        $jsonpath = $json.checkver.jp
    }
    if ($json.checkver.jsonpath) {
        $jsonpath = $json.checkver.jsonpath
    }
    if ($json.checkver.xpath) {
        $xpath = $json.checkver.xpath
    }

    if ($json.checkver.replace -and $json.checkver.replace.GetType() -eq [System.String]) {
        $replace = $json.checkver.replace
    }

    if (!$jsonpath -and !$regex -and !$xpath) {
        $regex = $json.checkver
    }

    $reverse = $json.checkver.reverse -and $json.checkver.reverse -eq 'true'

    $url = substitute $url $substitutions

    $state = New-Object psobject @{
        app      = (strip_ext $name);
        url      = $url;
        regex    = $regex;
        json     = $json;
        jsonpath = $jsonpath;
        xpath    = $xpath;
        reverse  = $reverse;
        replace  = $replace;
    }

    $wc.Headers.Add('Referer', (strip_filename $url))
    $wc.DownloadStringAsync($url, $state)
}

function next($er) {
    Write-Host "$App`: " -NoNewline
    Write-Host $er -ForegroundColor DarkRed
}

# wait for all to complete
$in_progress = $Queue.length
while ($in_progress -gt 0) {
    $ev = Wait-Event
    Remove-Event $ev.SourceIdentifier
    $in_progress--

    $state = $ev.SourceEventArgs.UserState
    $app = $state.app
    $json = $state.json
    $url = $state.url
    $regexp = $state.regex
    $jsonpath = $state.jsonpath
    $xpath = $state.xpath
    $reverse = $state.reverse
    $replace = $state.replace
    $expected_ver = $json.version
    $ver = ''

    $page = $ev.SourceEventArgs.Result
    $err = $ev.SourceEventArgs.Error
    if ($json.checkver.script) {
        $page = $json.checkver.script -join "`r`n" | Invoke-Expression
    }

    if($ev.Sender.ResponseHeaders -contains 'Last-Modified') {
        $lastModified = $ev.Sender.ResponseHeaders['Last-Modified']
        $modified = Get-Content $LastModifiedFile | ConvertFrom-Json
        if($null -ne $modified.$app) {
            $modified.$app = $lastModified
        } else {
            $modified | Add-Member -MemberType NoteProperty -Name $app -Value $lastModified
        }
        $modified | ConvertTo-Json | Set-Content $LastModifiedFile
    }

    if ($err) {
        if($err.Response.Headers -contains 'X-RateLimit-Limit' -and $err.Response.StatusCode -eq [System.Net.HttpStatusCode]::Forbidden) {
            debug $err.Response.Headers['X-RateLimit-Limit']
            debug $err.Response.Headers['X-RateLimit-Remaining']
            debug $err.Response.Headers['X-RateLimit-Reset']
        }
        if($err.Response.StatusCode -eq [System.Net.HttpStatusCode]::NotModified) {
            next "not modified"
            continue
        }
        next "$($err.message)`r`nURL $url is not valid"
        continue
    }

    if (!$regex -and $replace) {
        next "'replace' requires 're' or 'regex'"
        continue
    }

    if ($jsonpath) {
        $ver = json_path $page $jsonpath
        if (!$ver) {
            $ver = json_path_legacy $page $jsonpath
        }
        if (!$ver) {
            next "couldn't find '$jsonpath' in $url"
            continue
        }
    }

    if ($xpath) {
        $xml = [xml]$page
        # Find all `significant namespace declarations` from the XML file
        $nsList = $xml.SelectNodes("//namespace::*[not(. = ../../namespace::*)]")
        # Then add them into the NamespaceManager
        $nsmgr = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
        $nsList | ForEach-Object {
            $nsmgr.AddNamespace($_.LocalName, $_.Value)
        }
        # Getting version from XML, using XPath
        $ver = $xml.SelectSingleNode($xpath, $nsmgr).'#text'
        if (!$ver) {
            next "couldn't find '$xpath' in $url"
            continue
        }
    }

    if ($jsonpath -and $regexp) {
        $page = $ver
        $ver = ''
    }

    if ($xpath -and $regexp) {
        $page = $ver
        $ver = ''
    }

    if ($regexp) {
        $regex = New-Object System.Text.RegularExpressions.Regex($regexp)
        if ($reverse) {
            $match = $regex.Matches($page) | Select-Object -Last 1
        } else {
            $match = $regex.Matches($page) | Select-Object -First 1
        }

        if ($match -and $match.Success) {
            $matchesHashtable = @{}
            $regex.GetGroupNames() | ForEach-Object { $matchesHashtable.Add($_, $match.Groups[$_].Value) }
            $ver = $matchesHashtable['1']
            if ($replace) {
                $ver = $regex.Replace($match.Value, $replace)
            }
            if (!$ver) {
                $ver = $matchesHashtable['version']
            }
        } else {
            next "couldn't match '$regexp' in $url"
            continue
        }
    }

    if (!$ver) {
        next "couldn't find new version in $url"
        continue
    }

    # Skip actual only if versions are same and there is no -f
    if (($ver -eq $expected_ver) -and !$ForceUpdate -and $SkipUpdated) { continue }

    Write-Host "$App`: " -NoNewline

    # version hasn't changed (step over if forced update)
    if ($ver -eq $expected_ver -and !$ForceUpdate) {
        Write-Host $ver -ForegroundColor DarkGreen
        continue
    }

    Write-Host $ver -ForegroundColor DarkRed -NoNewline
    Write-Host " (scoop version is $expected_ver)" -NoNewline
    $update_available = (compare_versions $expected_ver $ver) -eq -1

    if ($json.autoupdate -and $update_available) {
        Write-Host ' autoupdate available' -ForegroundColor Cyan
    } else {
        Write-Host ''
    }

    # forcing an update implies updating, right?
    if ($ForceUpdate) { $Update = $true }

    if ($Update -and $json.autoupdate) {
        if ($ForceUpdate) {
            Write-Host 'Forcing autoupdate!' -ForegroundColor DarkMagenta
        }
        try {
            if ($Version -ne "") {
                $ver = $Version
            }
            autoupdate $App $Dir $json $ver $matchesHashtable
        } catch {
            error $_.Exception.Message
        }
    }
}
