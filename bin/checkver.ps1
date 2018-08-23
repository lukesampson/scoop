# checks websites for newer versions using an (optional) regular expression defined in the manifest
# use $dir to specify a manifest directory to check from, otherwise ./bucket is used
param(
    [String]$app,
    [String]$dir,
    [Switch]$update = $false,
    [Switch]$forceUpdate = $false
)

if (!$app -and $update) {
    # While developing the feature we only allow specific updates
    Write-Host "[ERROR] AUTOUPDATE CAN ONLY BE USED WITH A APP SPECIFIED" -f DarkRed
    exit
}

. "$psscriptroot\..\lib\core.ps1"
. "$psscriptroot\..\lib\manifest.ps1"
. "$psscriptroot\..\lib\config.ps1"
. "$psscriptroot\..\lib\buckets.ps1"
. "$psscriptroot\..\lib\autoupdate.ps1"
. "$psscriptroot\..\lib\json.ps1"
. "$psscriptroot\..\lib\versions.ps1"
. "$psscriptroot\..\lib\install.ps1" # needed for hash generation
. "$psscriptroot\..\lib\unix.ps1"

if(!$dir) { $dir = "$psscriptroot\..\bucket" }
$dir = resolve-path $dir

$search = "*"
if($app) { $search = $app }

# get apps to check
$queue = @()
Get-ChildItem $dir "$search.json" | ForEach-Object {
    $json = parse_json "$dir\$_"
    if($json.checkver) {
        $queue += ,@($_, $json)
    }
}

# clear any existing events
get-event | ForEach-Object {
    remove-event $_.sourceidentifier
}

$original = use_any_https_protocol

# start all downloads
$queue | ForEach-Object {
    $wc = New-Object Net.Webclient
    $wc.Headers.Add('User-Agent', (Get-UserAgent))
    register-objectevent $wc downloadstringcompleted -ea stop | out-null

    $name, $json = $_

    $githubRegex = "\/releases\/tag\/(?:v)?([\d.]+)"
    $sourceforgeRegex = "(?:.*)?\/(?:v)?([\d.]+)\/"

    $url = $json.homepage
    if($json.checkver.url) {
        $url = $json.checkver.url
    }
    $regex = ""
    $jsonpath = ""
    $replace = ""

    if ($json.checkver -eq "github") {
        if (!$json.homepage.StartsWith("https://github.com/")) {
            error "$name checkver expects the homepage to be a github repository"
        }
        $url = $json.homepage + "/releases/latest"
        $regex = $githubRegex
    }

    if ($json.checkver.github) {
        $url = $json.checkver.github + "/releases/latest"
        $regex = $githubRegex
    }

    if ($json.checkver -eq "sourceforge" -or $json.homepage.Contains("sourceforge.net") -or $json.checkver.sourceforge.path) {
        if ($json.homepage -match "\/\/sourceforge\.net\/projects\/(?<project>([\w-]+$|[\w-]+))(?:[/]?)" -or $json.homepage -match "\/\/(?<project>[\w-]+)\.sourceforge\.net") {
            $url = "https://sourceforge.net/projects/" + $matches['project'] + "/rss"
            $regex = "\/\/sourceforge\.net\/projects\/" + $matches['project'] + $sourceforgeRegex
            if ($json.checkver -ne "sourceforge" -and $json.checkver.GetType() -eq [System.String]) {
                $regex = $json.checkver
            }
        }
        else {
            $url = "https://sourceforge.net/projects/" + (strip_ext $name) + "/rss"
            $regex = "\/\/sourceforge\.net\/projects\/" + (strip_ext $name) + $sourceforgeRegex
        }
    }

    if ($json.checkver.sourceforge -and $json.checkver.sourceforge.GetType() -eq [System.String]) {
        $url = "https://sourceforge.net/projects/" + $json.checkver.sourceforge + "/rss"
        $regex = "\/\/sourceforge\.net\/projects\/" + $json.checkver.sourceforge + $sourceforgeRegex
    }

    if ($json.checkver.sourceforge.project) {
        $url = "https://sourceforge.net/projects/" + $json.checkver.sourceforge.project + "/rss"
        $regex = "\/\/sourceforge\.net\/projects\/" + $json.checkver.sourceforge.project + $sourceforgeRegex
    }

    if ($json.checkver.sourceforge.path) {
        $url = $url + "?path=" + $json.checkver.sourceforge.path
    }

    if($json.checkver.re) {
        $regex = $json.checkver.re
    }

    if($json.checkver.jp) {
        $jsonpath = $json.checkver.jp
    }

    if ($json.checkver.replace -and $json.checkver.replace.GetType() -eq [System.String]) {
        $replace = $json.checkver.replace
    }

    if(!$jsonpath -and !$regex) {
        $regex = $json.checkver
    }

    $reverse = $json.checkver.reverse -and $json.checkver.reverse -eq "true"

    $state = new-object psobject @{
        app = (strip_ext $name);
        url = $url;
        regex = $regex;
        json = $json;
        jsonpath = $jsonpath;
        reverse = $reverse;
        replace = $replace;
    }

    $wc.headers.add('Referer', (strip_filename $url))
    $wc.downloadstringasync($url, $state)
}

# wait for all to complete
$in_progress = $queue.length
while($in_progress -gt 0) {
    $ev = wait-event
    remove-event $ev.sourceidentifier
    $in_progress--

    $state = $ev.sourceeventargs.userstate
    $app = $state.app
    $json = $state.json
    $url = $state.url
    $expected_ver = $json.version
    $regexp = $state.regex
    $jsonpath = $state.jsonpath
    $reverse = $state.reverse
    $replace = $state.replace
    $ver = ""

    $err = $ev.sourceeventargs.error
    $page = $ev.sourceeventargs.result

    write-host "$app`: " -nonewline

    if($err) {
        write-host -f darkred $err.message
        write-host -f darkred "URL $url is not valid"
        continue
    }

    if(!$regex -and $replace) {
        write-host -f darkred "'replace' requires 're'"
        continue
    }

    if($jsonpath) {
        $ver = json_path $page $jsonpath
        if(!$ver) {
            $ver = json_path_legacy $page $jsonpath
        }
        if(!$ver) {
            write-host -f darkred "couldn't find '$jsonpath' in $url"
            continue
        }
    }

    if($jsonpath -and $regexp) {
        $page = $ver
        $ver = ""
    }

    if($regexp) {
        $regex = new-object System.Text.RegularExpressions.Regex($regexp)
        if($reverse) {
            $match = $regex.matches($page) | select-object -last 1
        } else {
            $match = $regex.matches($page) | select-object -first 1
        }

        if($match -and $match.Success) {
            $matchesHashtable = @{}
            $regex.GetGroupNames() | ForEach-Object { $matchesHashtable.Add($_, $match.Groups[$_].Value) }
            $ver = $matchesHashtable['1']
            if ($replace) {
                $ver = $regex.replace($match.Value, $replace)
            }
            if(!$ver) {
                $ver = $matchesHashtable['version']
            }
        } else {
            write-host -f darkred "couldn't match '$regexp' in $url"
            continue
        }
    }

    if(!$ver) {
        write-host -f darkred "couldn't find new version in $url"
        continue
    }

    if($ver -eq $expected_ver -and $forceUpdate -eq $false) {
        # version hasn't changed (step over if forced update)
        write-host "$ver" -f darkgreen
        continue
    }

    write-host "$ver" -f darkred -nonewline
    write-host " (scoop version is $expected_ver)" -NoNewline
    $update_available = (compare_versions $expected_ver $ver) -eq -1

    if ($json.autoupdate -and $update_available) {
        Write-Host " autoupdate available" -f Cyan
    } else {
        Write-Host ""
    }

    if($forceUpdate) {
        # forcing an update implies updating, right?
        $update = $true
    }

    if($update -and $json.autoupdate) {
        if($forceUpdate) {
            Write-Host "Forcing autoupdate!" -f DarkMagenta
        }
        try {
            autoupdate $app $dir $json $ver $matchesHashtable
        } catch {
            error $_.exception.message
        }
    }
}

set_https_protocols $original

<#
write-host "checking $(strip_ext (fname $_))..." -nonewline
$expected_ver = $json.version

$url = $json.checkver.url
if(!$url) { $url = $json.homepage }

$regexp = $json.checkver.re
if(!$regexp) { $regexp = $json.checkver }

$page = $wc.downloadstring($url)

if($page -match $regexp) {
    $ver = $matches[1]
    if($ver -eq $expected_ver) {
        write-host "$ver" -f darkgreen
    } else {
        write-host "$ver" -f darkred -nonewline
        write-host " (scoop version is $expected_ver)"
    }

} else {
    write-host "couldn't match '$regexp' in $url" -f darkred
}
#>
