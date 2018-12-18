<#
TODO
 - add a github release autoupdate type
 - tests (single arch, without hashes etc.)
 - clean up
#>
. "$psscriptroot\..\lib\json.ps1"

. "$psscriptroot/core.ps1"
. "$psscriptroot/json.ps1"

function find_hash_in_rdf([String] $url, [String] $filename) {
    $data = $null
    try {
        # Download and parse RDF XML file
        $wc = New-Object Net.Webclient
        $wc.Headers.Add('Referer', (strip_filename $url))
        $wc.Headers.Add('User-Agent', (Get-UserAgent))
        [xml]$data = $wc.downloadstring($url)
    } catch [system.net.webexception] {
        write-host -f darkred $_
        write-host -f darkred "URL $url is not valid"
        return $null
    }

    # Find file content
    $digest = $data.RDF.Content | Where-Object { [String]$_.about -eq $filename }

    return format_hash $digest.sha256
}

function find_hash_in_textfile([String] $url, [String] $basename, [String] $regex) {
    $hashfile = $null

    try {
        $wc = New-Object Net.Webclient
        $wc.Headers.Add('Referer', (strip_filename $url))
        $wc.Headers.Add('User-Agent', (Get-UserAgent))
        $hashfile = $wc.downloadstring($url)
    } catch [system.net.webexception] {
        write-host -f darkred $_
        write-host -f darkred "URL $url is not valid"
        return
    }

    # find single line hash in $hashfile (will be overridden by $regex)
    if ($regex.Length -eq 0) {
        $normalRegex = "^([a-fA-F0-9]+)$"
    } else {
        $normalRegex = $regex
    }

    $normalRegex = substitute $normalRegex @{'$basename' = [regex]::Escape($basename)}
    if ($hashfile -match $normalRegex) {
        $hash = $matches[1] -replace ' ',''
    }

    # convert base64 encoded hash values
    if ($hash -match '^(?:[A-Za-z0-9+\/]{4})*(?:[A-Za-z0-9+\/]{2}==|[A-Za-z0-9+\/]{3}=|[A-Za-z0-9+\/]{4})$') {
        $base64 = $matches[0]
        if(!($hash -match '^[a-fA-F0-9]+$') -and $hash.length -notin @(32, 40, 64, 128)) {
            try {
                $hash = ([System.Convert]::FromBase64String($base64) | ForEach-Object { $_.ToString('x2') }) -join ''
            } catch {
                $hash = $hash
            }
        }
    }

    # find hash with filename in $hashfile (will be overridden by $regex)
    if ($hash.Length -eq 0 -and $regex.Length -eq 0) {
        $filenameRegex = "([a-fA-F0-9]{32,128})[\x20\t]+.*`$basename(?:[\x20\t]+\d+)?"
        $filenameRegex = substitute $filenameRegex @{'$basename' = [regex]::Escape($basename)}
        if ($hashfile -match $filenameRegex) {
            $hash = $matches[1]
        }
        $metalinkRegex = "<hash[^>]+>([a-fA-F0-9]{64})"
        if ($hashfile -match $metalinkRegex) {
            $hash = $matches[1]
        }
    }

    return format_hash $hash
}

function find_hash_in_json([String] $url, [String] $basename, [String] $jsonpath) {
    $man = $null

    try {
        $wc = New-Object Net.Webclient
        $wc.Headers.Add('Referer', (strip_filename $url))
        $wc.Headers.Add('User-Agent', (Get-UserAgent))
        $man = $wc.DownloadString($url)
    } catch [system.net.webexception] {
        write-host -f darkred $_
        write-host -f darkred "URL $url is not valid"
        return
    }
    $hash = json_path $man $jsonpath $basename
    if(!$hash) {
        $hash = json_path_legacy $man $jsonpath $basename
    }
    return format_hash $hash
}

function find_hash_in_headers([String] $url) {
    $hash = $null

    try {
        $req = [System.Net.WebRequest]::Create($url)
        $req.Referer = (strip_filename $url)
        $req.AllowAutoRedirect = $false
        $req.UserAgent = (Get-UserAgent)
        $req.Timeout = 2000
        $req.Method = 'HEAD'
        $res = $req.GetResponse()
        if(([int]$response.StatusCode -ge 300) -and ([int]$response.StatusCode -lt 400)) {
            if($res.Headers['Digest'] -match 'SHA-256=([^,]+)' -or $res.Headers['Digest'] -match 'SHA=([^,]+)' -or $res.Headers['Digest'] -match 'MD5=([^,]+)') {
                $hash = ([System.Convert]::FromBase64String($matches[1]) | ForEach-Object { $_.ToString('x2') }) -join ''
                debug $hash
            }
        }
        $res.Close()
    } catch [system.net.webexception] {
        write-host -f darkred $_
        write-host -f darkred "URL $url is not valid"
        return
    }

    return format_hash $hash
}

function get_hash_for_app([String] $app, $config, [String] $version, [String] $url, [Hashtable] $substitutions) {
    $hash = $null

    <#
    TODO implement more hashing types
    `extract` Should be able to extract from origin page source (checkver)
    `rdf` Find hash from a RDF Xml file
    `download` Last resort, download the real file and hash it
    #>
    $hashmode = $config.mode
    $basename = url_remote_filename($url)

    $hashfile_url = substitute $config.url @{
        '$url'      = (strip_fragment $url)
        '$baseurl'  = (strip_filename (strip_fragment $url)).TrimEnd('/')
        '$basename' = $basename
    }
    $hashfile_url = substitute $hashfile_url $substitutions
    if($hashfile_url) {
        write-host -f DarkYellow 'Searching hash for ' -NoNewline
        write-host -f Green $(url_remote_filename $url) -NoNewline
        write-host -f DarkYellow ' in ' -NoNewline
        write-host -f Green $hashfile_url
    }

    if($hashmode.Length -eq 0 -and $config.url.Length -ne 0) {
        $hashmode = 'extract'
    }

    $jsonpath = ''
    if ($config.jp) {
        $jsonpath = $config.jp
        $hashmode = 'json'
    }
    if ($config.jsonpath) {
        $jsonpath = $config.jsonpath
        $hashmode = 'json'
    }
    $regex = ''
    if ($config.find) {
        $regex = $config.find
    }
    if ($config.regex) {
        $regex = $config.regex
    }

    if (!$hashfile_url -and $url -match "(?:downloads\.)?sourceforge.net\/projects?\/(?<project>[^\/]+)\/(?:files\/)?(?<file>.*)") {
        $hashmode = 'sourceforge'
        # change the URL because downloads.sourceforge.net doesn't have checksums
        $hashfile_url = (strip_filename (strip_fragment "https://sourceforge.net/projects/$($matches['project'])/files/$($matches['file'])")).TrimEnd('/')
        $hash = find_hash_in_textfile $hashfile_url $basename '"$basename":.*?"sha1":\s"([a-fA-F0-9]{40})"'
    }

    switch ($hashmode) {
        'extract' {
            $hash = find_hash_in_textfile $hashfile_url $basename $regex
        }
        'json' {
            $hash = find_hash_in_json $hashfile_url $basename $jsonpath
        }
        'rdf' {
            $hash = find_hash_in_rdf $hashfile_url $basename
        }
        'metalink' {
            $hash = find_hash_in_headers $url
            if(!$hash) {
                $hash = find_hash_in_textfile "$url.meta4"
            }
        }
    }

    if($hash) {
        # got one!
        write-host -f DarkYellow 'Found: ' -NoNewline
        write-host -f Green $hash -NoNewline
        write-host -f DarkYellow ' using ' -NoNewline
        write-host -f Green  "$((Get-Culture).TextInfo.ToTitleCase($hashmode)) Mode"
        return $hash
    } elseif($hashfile_url) {
        write-host -f DarkYellow "Could not find hash in $hashfile_url"
    }

    write-host -f DarkYellow 'Downloading ' -NoNewline
    write-host -f Green $(url_remote_filename $url) -NoNewline
    write-host -f DarkYellow ' to compute hashes!'
    try {
        dl_with_cache $app $version $url $null $null $true
    } catch [system.net.webexception] {
        write-host -f darkred $_
        write-host -f darkred "URL $url is not valid"
        return $null
    }
    $file = fullpath (cache_path $app $version $url)
    $hash = compute_hash $file 'sha256'
    write-host -f DarkYellow 'Computed hash: ' -NoNewline
    write-host -f Green $hash
    return $hash
}

function update_manifest_with_new_version($man, [String] $version, [String] $url, [String] $hash, $architecture = $null) {
    $man.version = $version

    if ($null -eq $architecture) {
        if ($man.url -is [System.Array]) {
            $man.url[0] = $url
            $man.hash[0] = $hash
        } else {
            $man.url = $url
            $man.hash = $hash
        }
    } else {
        # If there are multiple urls we replace the first one
        if ($man.architecture.$architecture.url -is [System.Array]) {
            $man.architecture.$architecture.url[0] = $url
            $man.architecture.$architecture.hash[0] = $hash
        } else {
            $man.architecture.$architecture.url = $url
            $man.architecture.$architecture.hash = $hash
        }
    }
}

function update_manifest_prop([String] $prop, $man, [Hashtable] $substitutions) {
    # first try the global property
    if ($man.$prop -and $man.autoupdate.$prop) {
        $man.$prop = substitute $man.autoupdate.$prop $substitutions
    }

    # check if there are architecture specific variants
    if ($man.architecture -and $man.autoupdate.architecture) {
        $man.architecture | Get-Member -MemberType NoteProperty | ForEach-Object {
            $architecture = $_.Name
            if ($man.architecture.$architecture.$prop -and $man.autoupdate.architecture.$architecture.$prop) {
                $man.architecture.$architecture.$prop = substitute (arch_specific $prop $man.autoupdate $architecture) $substitutions
            }
        }
    }
}

function get_version_substitutions([String] $version, [Hashtable] $customMatches) {
    $firstPart = $version.Split('-') | Select-Object -first 1
    $lastPart = $version.Split('-') | Select-Object -last 1
    $versionVariables = @{
        '$version'           = $version
        '$underscoreVersion' = ($version -replace "\.", "_")
        '$dashVersion'       = ($version -replace "\.", "-")
        '$cleanVersion'      = ($version -replace "\.", "")
        '$majorVersion'      = $firstPart.Split('.') | Select-Object -first 1
        '$minorVersion'      = $firstPart.Split('.') | Select-Object -skip 1 -first 1
        '$patchVersion'      = $firstPart.Split('.') | Select-Object -skip 2 -first 1
        '$buildVersion'      = $firstPart.Split('.') | Select-Object -skip 3 -first 1
        '$preReleaseVersion' = $lastPart
    }
    if($version -match "(?<head>\d+\.\d+(?:\.\d+)?)(?<tail>.*)") {
        $versionVariables.Set_Item('$matchHead', $matches['head'])
        $versionVariables.Set_Item('$matchTail', $matches['tail'])
    }
    if($customMatches) {
        $customMatches.GetEnumerator() | ForEach-Object {
            if($_.Name -ne "0") {
                $versionVariables.Set_Item('$match' + (Get-Culture).TextInfo.ToTitleCase($_.Name), $_.Value)
            }
        }
    }
    return $versionVariables
}

function autoupdate([String] $app, $dir, $man, [String] $version, [Hashtable] $matches) {
    Write-Host -f DarkCyan "Autoupdating $app"
    $has_changes = $false
    $has_errors = $false
    [Bool]$valid = $true
    $substitutions = get_version_substitutions $version $matches

    if ($man.url) {
        # create new url
        $url   = substitute $man.autoupdate.url $substitutions
        $valid = $true

        if($valid) {
            # create hash
            $hash = get_hash_for_app $app $man.autoupdate.hash $version $url $substitutions
            if ($null -eq $hash) {
                $valid = $false
                Write-Host -f DarkRed "Could not find hash!"
            }
        }

        # write changes to the json object
        if ($valid) {
            $has_changes = $true
            update_manifest_with_new_version $man $version $url $hash
        } else {
            $has_errors = $true
            throw "Could not update $app"
        }
    } else {
        if ($man.architecture | Get-Member -MemberType NoteProperty) {
            # JSOn
            $properties = $man.architecture | Get-Member -MemberType NoteProperty
        } else {
            # YAML
            # Convert orderedDictionary into pscustom object to preserver implementation
            $properties = ([pscustomobject] $man.architecture) | Get-Member -MemberType NoteProperty
        }

        $properties | ForEach-Object {
            $valid = $true
            $architecture = $_.Name

            # create new url
            $url = substitute (arch_specific 'url' $man.autoupdate $architecture) $substitutions
            $valid = $true

            if($valid) {
                # create hash
                $hash = get_hash_for_app $app (arch_specific "hash" $man.autoupdate $architecture) $version $url $substitutions
                if ($null -eq $hash) {
                    $valid = $false
                    Write-Host -f DarkRed "Could not find hash!"
                }
            }

            # write changes to the json object
            if ($valid) {
                $has_changes = $true
                update_manifest_with_new_version $man $version $url $hash $architecture
            } else {
                $has_errors = $true
                throw "Could not update $app $architecture"
            }
        }
    }

    # update properties
    update_manifest_prop "extract_dir" $man $substitutions

    # update license
    update_manifest_prop "license" $man $substitutions

    if ($has_changes -and !$has_errors) {
        # write file
        Write-Host "Writing updated $app manifest" -ForegroundColor DarkGreen

        $extension = Get-Extension (Get-ChildItem $dir "$app.*")
        Scoop-WriteManifest "$dir\$app.$extension" $man

        # notes
        if ($man.autoupdate.note) {
            Write-Host ''
            Write-Host $man.autoupdate.note -ForegroundColor Yellow
        }
    } else {
        Write-Host "No updates for $app" -ForegroundColor DarkGray
    }
}
