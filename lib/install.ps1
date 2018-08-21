. "$psscriptroot/autoupdate.ps1"
. "$psscriptroot/buckets.ps1"


function nightly_version($date, $quiet = $false) {
    $date_str = $date.tostring("yyyyMMdd")
    if (!$quiet) {
        warn "This is a nightly version. Downloaded files won't be verified."
    }
    "nightly-$date_str"
}

function install_app($app, $architecture, $global, $suggested, $use_cache = $true, $check_hash = $true) {
    $app, $bucket, $null = parse_app $app
    $app, $manifest, $bucket, $url = locate $app $bucket

    if(!$manifest) {
        abort "Couldn't find manifest for '$app'$(if($url) { " at the URL $url" })."
    }

    $version = $manifest.version
    if(!$version) { abort "Manifest doesn't specify a version." }
    if($version -match '[^\w\.\-\+_]') {
        abort "Manifest version has unsupported character '$($matches[0])'."
    }

    $is_nightly = $version -eq 'nightly'
    if ($is_nightly) {
        $version = nightly_version $(get-date)
        $check_hash = $false
    }

    if(!(supports_architecture $manifest $architecture)) {
        write-host -f DarkRed "'$app' doesn't support $architecture architecture!"
        return
    }

    write-output "Installing '$app' ($version) [$architecture]"

    $dir = ensure (versiondir $app $version $global)
    $original_dir = $dir # keep reference to real (not linked) directory
    $persist_dir = persistdir $app $global

    $fname = dl_urls $app $version $manifest $bucket $architecture $dir $use_cache $check_hash
    unpack_inno $fname $manifest $dir
    pre_install $manifest $architecture
    run_installer $fname $manifest $architecture $dir $global
    ensure_install_dir_not_in_path $dir $global
    $dir = link_current $dir
    create_shims $manifest $dir $global $architecture
    create_startmenu_shortcuts $manifest $dir $global $architecture
    install_psmodule $manifest $dir $global
    if($global) { ensure_scoop_in_path $global } # can assume local scoop is in path
    env_add_path $manifest $dir $global
    env_set $manifest $dir $global

    # persist data
    persist_data $manifest $original_dir $persist_dir

    post_install $manifest $architecture

    # save info for uninstall
    save_installed_manifest $app $bucket $dir $url
    save_install_info @{ 'architecture' = $architecture; 'url' = $url; 'bucket' = $bucket } $dir

    if($manifest.suggest) {
        $suggested[$app] = $manifest.suggest
    }

    success "'$app' ($version) was installed successfully!"

    show_notes $manifest $dir $original_dir $persist_dir
    cmd.exe /c "refreshenv"
}

function locate($app, $bucket) {
    $manifest, $url = $null, $null

    # check if app is a URL or UNC path
    if($app -match '^(ht|f)tps?://|\\\\') {
        $url = $app
        $app = appname_from_url $url
        $manifest = url_manifest $url
    } else {
        # check buckets
        $manifest, $bucket = find_manifest $app $bucket

        if(!$manifest) {
            # couldn't find app in buckets: check if it's a local path
            $path = $app
            if(!$path.endswith('.json')) { $path += '.json' }
            if(test-path $path) {
                $url = "$(resolve-path $path)"
                $app = appname_from_url $url
                $manifest, $bucket = url_manifest $url
            }
        }
    }

    return $app, $manifest, $bucket, $url
}

function dl_with_cache($app, $version, $url, $to, $cookies = $null, $use_cache = $true) {
    $cached = fullpath (cache_path $app $version $url)

    if(!(test-path $cached) -or !$use_cache) {
        $null = ensure $cachedir
        do_dl $url "$cached.download" $cookies
        Move-Item "$cached.download" $cached -force
    } else { write-host "Loading $(url_remote_filename $url) from cache"}

    if (!($null -eq $to)) {
        Copy-Item $cached $to
    }
}

function use_any_https_protocol() {
    $original = "$([System.Net.ServicePointManager]::SecurityProtocol)"
    $available = [string]::join(', ', [Enum]::GetNames([System.Net.SecurityProtocolType]))

    # use whatever protocols are available that the server supports
    set_https_protocols $available

    return $original
}

function set_https_protocols($protocols) {
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType] $protocols
    } catch {
        [System.Net.ServicePointManager]::SecurityProtocol = "Tls,Tls11,Tls12"
    }
}

function do_dl($url, $to, $cookies) {
    $original_protocols = use_any_https_protocol
    $progress = [console]::isoutputredirected -eq $false -and
        $host.name -ne 'Windows PowerShell ISE Host'

    try {
        $url = handle_special_urls $url
        dl $url $to $cookies $progress
    } catch {
        $e = $_.exception
        if($e.innerexception) { $e = $e.innerexception }
        throw $e
    } finally {
        set_https_protocols $original_protocols
    }
}

function aria_exit_code($exitcode) {
    $codes = @{
        0='All downloads were successful'
        1='An unknown error occurred'
        2='Timeout'
        3='Resource was not found'
        4='Aria2 saw the specified number of "resource not found" error. See --max-file-not-found option'
        5='Download aborted because download speed was too slow. See --lowest-speed-limit option'
        6='Network problem occurred.'
        7='There were unfinished downloads. This error is only reported if all finished downloads were successful and there were unfinished downloads in a queue when aria2 exited by pressing Ctrl-C by an user or sending TERM or INT signal'
        8='Remote server did not support resume when resume was required to complete download'
        9='There was not enough disk space available'
        10='Piece length was different from one in .aria2 control file. See --allow-piece-length-change option'
        11='Aria2 was downloading same file at that moment'
        12='Aria2 was downloading same info hash torrent at that moment'
        13='File already existed. See --allow-overwrite option'
        14='Renaming file failed. See --auto-file-renaming option'
        15='Aria2 could not open existing file'
        16='Aria2 could not create new file or truncate existing file'
        17='File I/O error occurred'
        18='Aria2 could not create directory'
        19='Name resolution failed'
        20='Aria2 could not parse Metalink document'
        21='FTP command failed'
        22='HTTP response header was bad or unexpected'
        23='Too many redirects occurred'
        24='HTTP authorization failed'
        25='Aria2 could not parse bencoded file (usually ".torrent" file)'
        26='".torrent" file was corrupted or missing information that aria2 needed'
        27='Magnet URI was bad'
        28='Bad/unrecognized option was given or unexpected option argument was given'
        29='The remote server was unable to handle the request due to a temporary overloading or maintenance'
        30='Aria2 could not parse JSON-RPC request'
        31='Reserved. Not used'
        32='Checksum validation failed'
    }
    if($null -eq $codes[$exitcode]) {
        return 'An unknown error occurred'
    }
    return $codes[$exitcode]
}

function dl_with_cache_aria2($app, $version, $manifest, $architecture, $dir, $cookies = $null, $use_cache = $true, $check_hash = $true) {
    $data = @{}
    $urls = @(url $manifest $architecture)

    # aria2 input file
    $urlstxt = "$cachedir\$app.txt"
    $urlstxt_content = ''
    $has_downloads = $false

    # aria2 options
    $options = @(
        "--input-file='$urlstxt'"
        "--user-agent='$(Get-UserAgent)'"
        "--allow-overwrite=true"
        "--auto-file-renaming=false"
        "--retry-wait=$(get_config 'aria2-retry-wait' 2)"
        "--split=$(get_config 'aria2-split' 5)"
        "--max-connection-per-server=$(get_config 'aria2-max-connection-per-server' 5)"
        "--min-split-size=$(get_config 'aria2-min-split-size' '5M')"
        "--console-log-level=warn"
        "--enable-color=false"
        "--no-conf=true"
    )

    if($cookies) {
        $options += "--header='Cookie: $(cookie_header $cookies)'"
    }

    $proxy = get_config 'proxy'
    if($proxy -ne 'none') {
        if([Net.Webrequest]::DefaultWebProxy.Address) {
            $options += "--all-proxy='$([Net.Webrequest]::DefaultWebProxy.Address.Authority)'"
        }
        if([Net.Webrequest]::DefaultWebProxy.Credentials.UserName) {
            $options += "--all-proxy-user='$([Net.Webrequest]::DefaultWebProxy.Credentials.UserName)'"
        }
        if([Net.Webrequest]::DefaultWebProxy.Credentials.Password) {
            $options += "--all-proxy-passwd='$([Net.Webrequest]::DefaultWebProxy.Credentials.Password)'"
        }
    }

    $more_options = get_config 'aria2-options'
    if($more_options) {
        $options += $more_options
    }

    foreach($url in $urls) {
        $data.$url = @{
            'filename' = url_filename $url
            'target' = "$dir\$(url_filename $url)"
            'cachename' = fname (cache_path $app $version $url)
            'source' = fullpath (cache_path $app $version $url)
        }

        if(!(test-path $data.$url.source)) {
            $has_downloads = $true
            # create aria2 input file content
            $urlstxt_content += "$url`n"
            if(!$url.Contains('sourceforge.net')) {
                $urlstxt_content += "    referer=$(strip_filename $url)`n"
            }
            $urlstxt_content += "    dir=$cachedir`n"
            $urlstxt_content += "    out=$($data.$url.cachename)`n"
        } else {
            Write-Host "Loading " -NoNewline
            Write-Host $(url_remote_filename $url) -f Cyan -NoNewline
            Write-Host " from cache."
        }
    }

    if($has_downloads) {
        # write aria2 input file
        Set-Content -Path $urlstxt $urlstxt_content

        # build aria2 command
        $aria2 = "& '$(aria2_path)' $($options -join ' ')"

        # handle aria2 console output
        Write-Host "Starting download with aria2 ..."
        $prefix = "Download: "
        Invoke-Expression $aria2 | ForEach-Object {
            if([String]::IsNullOrWhiteSpace($_)) {
                # skip blank lines
                return
            }
            Write-Host $prefix -NoNewline
            if($_.StartsWith('(OK):')) {
                Write-Host $_ -f Green
            } elseif($_.StartsWith('[') -and $_.EndsWith(']')) {
                Write-Host $_ -f Cyan
            } else {
                Write-Host $_ -f Gray
            }
        }

        if($lastexitcode -gt 0) {
            error "Download failed! (Error $lastexitcode) $(aria_exit_code $lastexitcode)"
            debug $urlstxt_content
            debug $aria2
            abort $(new_issue_msg $app $bucket "download via aria2 failed")
        }

        # remove aria2 input file when done
        if(test-path($urlstxt)) {
            Remove-Item $urlstxt
        }
    }

    foreach($url in $urls) {

        # run hash checks
        if($check_hash) {
            $manifest_hash = hash_for_url $manifest $url $architecture
            $ok, $err = check_hash $data.$url.source $manifest_hash $(show_app $app $bucket)
            if(!$ok) {
                error $err
                if(test-path $data.$url.source) {
                    # rm cached file
                    Remove-Item -force $data.$url.source
                }
                if($url.Contains('sourceforge.net')) {
                    Write-Host -f yellow 'SourceForge.net is known for causing hash validation fails. Please try again before opening a ticket.'
                }
                abort $(new_issue_msg $app $bucket "hash check failed")
            }
        }

        # copy or move file to target location
        if(!(test-path $data.$url.source) ) {
            abort $(new_issue_msg $app $bucket "cached file not found")
        }
        if($use_cache) {
            Copy-Item $data.$url.source $data.$url.target
        } else {
            Move-Item $data.$url.source $data.$url.target -force
        }
    }
}

# download with filesize and progress indicator
function dl($url, $to, $cookies, $progress) {
    $wreq = [net.webrequest]::create($url)
    if($wreq -is [net.httpwebrequest]) {
        $wreq.useragent = Get-UserAgent
        if (-not ($url -imatch "sourceforge\.net")) {
            $wreq.referer = strip_filename $url
        }
        if($cookies) {
            $wreq.headers.add('Cookie', (cookie_header $cookies))
        }
    }

    $wres = $wreq.getresponse()
    $total = $wres.ContentLength
    if($total -eq -1 -and $wreq -is [net.ftpwebrequest]) {
        $total = ftp_file_size($url)
    }

    if ($progress -and ($total -gt 0)) {
        [console]::CursorVisible = $false
        function dl_onProgress($read) {
            dl_progress $read $total $url
        }
    } else {
        write-host "Downloading $url ($(filesize $total))..."
        function dl_onProgress {
            #no op
        }
    }

    try {
        $s = $wres.getresponsestream()
        $fs = [io.file]::openwrite($to)
        $buffer = new-object byte[] 2048
        $totalRead = 0
        $sw = [diagnostics.stopwatch]::StartNew()

        dl_onProgress $totalRead
        while(($read = $s.read($buffer, 0, $buffer.length)) -gt 0) {
            $fs.write($buffer, 0, $read)
            $totalRead += $read
            if ($sw.elapsedmilliseconds -gt 100) {
                $sw.restart()
                dl_onProgress $totalRead
            }
        }
        $sw.stop()
        dl_onProgress $totalRead
    } finally {
        if ($progress) {
            [console]::CursorVisible = $true
            write-host
        }
        if ($fs) {
            $fs.close()
        }
        if ($s) {
            $s.close();
        }
        $wres.close()
    }
}

function dl_progress_output($url, $read, $total, $console) {
    $filename = url_remote_filename $url

    # calculate current percentage done
    $p = [math]::Round($read / $total * 100, 0)

    # pre-generate LHS and RHS of progress string
    # so we know how much space we have
    $left  = "$filename ($(filesize $total))"
    $right = [string]::Format("{0,3}%", $p)

    # calculate remaining width for progress bar
    $midwidth  = $console.BufferSize.Width - ($left.Length + $right.Length + 8)

    # calculate how many characters are completed
    $completed = [math]::Abs([math]::Round(($p / 100) * $midwidth, 0) - 1)

    # generate dashes to symbolise completed
    if ($completed -gt 1) {
        $dashes = [string]::Join("", ((1..$completed) | ForEach-Object {"="}))
    }

    # this is why we calculate $completed - 1 above
    $dashes += switch($p) {
        100 {"="}
        default {">"}
    }

    # the remaining characters are filled with spaces
    $spaces = switch($dashes.Length) {
        $midwidth {[string]::Empty}
        default {
            [string]::Join("", ((1..($midwidth - $dashes.Length)) | ForEach-Object {" "}))
        }
    }

    "$left [$dashes$spaces] $right"
}

function dl_progress($read, $total, $url) {
    $console = $host.UI.RawUI;
    $left  = $console.CursorPosition.X;
    $top   = $console.CursorPosition.Y;
    $width = $console.BufferSize.Width;

    if($read -eq 0) {
        $maxOutputLength = $(dl_progress_output $url 100 $total $console).length
        if (($left + $maxOutputLength) -gt $width) {
            # not enough room to print progress on this line
            # print on new line
            write-host
            $left = 0
            $top  = $top + 1
        }
    }

    write-host $(dl_progress_output $url $read $total $console) -nonewline
    [console]::SetCursorPosition($left, $top)
}

function dl_urls($app, $version, $manifest, $bucket, $architecture, $dir, $use_cache = $true, $check_hash = $true) {
    # we only want to show this warning once
    if(!$use_cache) { warn "Cache is being ignored." }

    # can be multiple urls: if there are, then msi or installer should go last,
    # so that $fname is set properly
    $urls = @(url $manifest $architecture)

    # can be multiple cookies: they will be used for all HTTP requests.
    $cookies = $manifest.cookie

    $fname = $null

    # extract_dir and extract_to in manifest are like queues: for each url that
    # needs to be extracted, will get the next dir from the queue
    $extract_dirs = @(extract_dir $manifest $architecture)
    $extract_tos = @(extract_to $manifest $architecture)
    $extracted = 0;

    # download first
    if(aria2_enabled) {
        dl_with_cache_aria2 $app $version $manifest $architecture $dir $cookies $use_cache $check_hash
    } else {
        foreach($url in $urls) {
            $fname = url_filename $url

            try {
                dl_with_cache $app $version $url "$dir\$fname" $cookies $use_cache
            } catch {
                write-host -f darkred $_
                abort "URL $url is not valid"
            }

            if($check_hash) {
                $manifest_hash = hash_for_url $manifest $url $architecture
                $ok, $err = check_hash "$dir\$fname" $manifest_hash $(show_app $app $bucket)
                if(!$ok) {
                    error $err
                    $cached = cache_path $app $version $url
                    if(test-path $cached) {
                        # rm cached file
                        Remove-Item -force $cached
                    }
                    if($url.Contains('sourceforge.net')) {
                        Write-Host -f yellow 'SourceForge.net is known for causing hash validation fails. Please try again before opening a ticket.'
                    }
                    abort $(new_issue_msg $app $bucket "hash check failed")
                }
            }
        }
    }

    foreach($url in $urls) {
        $fname = url_filename $url

        $extract_dir = $extract_dirs[$extracted]
        $extract_to = $extract_tos[$extracted]

        # work out extraction method, if applicable
        $extract_fn = $null
        if($fname -match '\.zip$') { # unzip
            $extract_fn = 'unzip'
        } elseif($fname -match '\.msi$') {
            # check manifest doesn't use deprecated install method
            $msi = msi $manifest $architecture
            if(!$msi) {
                $useLessMsi = get_config MSIEXTRACT_USE_LESSMSI
                if ($useLessMsi -eq $true) {
                    $extract_fn, $extract_dir = lessmsi_config $extract_dir
                }
                else {
                    $extract_fn = 'extract_msi'
                }
            } else {
                warn "MSI install is deprecated. If you maintain this manifest, please refer to the manifest reference docs."
            }
        } elseif(file_requires_7zip $fname) { # 7zip
            if(!(7zip_installed)) {
                warn "Aborting. You'll need to run 'scoop uninstall $app' to clean up."
                abort "7-zip is required. You can install it with 'scoop install 7zip'."
            }
            $extract_fn = 'extract_7zip'
        }

        if($extract_fn) {
            Write-Host "Extracting " -NoNewline
            Write-Host $fname -f Cyan -NoNewline
            Write-Host " ... " -NoNewline
            $null = mkdir "$dir\_tmp"
            & $extract_fn "$dir\$fname" "$dir\_tmp"
            Remove-Item "$dir\$fname"
            if ($extract_to) {
                $null = mkdir "$dir\$extract_to" -force
            }
            # fails if zip contains long paths (e.g. atom.json)
            #cp "$dir\_tmp\$extract_dir\*" "$dir\$extract_to" -r -force -ea stop
            try {
                movedir "$dir\_tmp\$extract_dir" "$dir\$extract_to"
            }
            catch {
                error $_
                abort $(new_issue_msg $app $bucket "extract_dir error")
            }

            if(test-path "$dir\_tmp") { # might have been moved by movedir
                try {
                    Remove-Item -r -force "$dir\_tmp" -ea stop
                } catch [system.io.pathtoolongexception] {
                    & "$env:COMSPEC" /c "rmdir /s /q $dir\_tmp"
                } catch [system.unauthorizedaccessexception] {
                    warn "Couldn't remove $dir\_tmp: unauthorized access."
                }
            }

            Write-Host "done." -f Green

            $extracted++
        }
    }

    $fname # returns the last downloaded file
}

function lessmsi_config ($extract_dir) {
    $extract_fn = 'extract_lessmsi'
    if ($extract_dir) {
        $extract_dir = join-path SourceDir $extract_dir
    }
    else {
        $extract_dir = "SourceDir"
    }

    $extract_fn, $extract_dir
}

function cookie_header($cookies) {
    if(!$cookies) { return }

    $vals = $cookies.psobject.properties | ForEach-Object {
        "$($_.name)=$($_.value)"
    }

    [string]::join(';', $vals)
}

function is_in_dir($dir, $check) {
    $check = "$(fullpath $check)"
    $dir = "$(fullpath $dir)"
    $check -match "^$([regex]::escape("$dir"))(\\|`$)"
}

function ftp_file_size($url) {
    $request = [net.ftpwebrequest]::create($url)
    $request.method = [net.webrequestmethods+ftp]::getfilesize
    $request.getresponse().contentlength
}

# hashes
function hash_for_url($manifest, $url, $arch) {
    $hashes = @(hash $manifest $arch) | Where-Object { $_ -ne $null };

    if($hashes.length -eq 0) { return $null }

    $urls = @(url $manifest $arch)

    $index = [array]::indexof($urls, $url)
    if($index -eq -1) { abort "Couldn't find hash in manifest for '$url'." }

    @($hashes)[$index]
}

# returns (ok, err)
function check_hash($file, $hash, $app_name) {
    $file = fullpath $file
    if(!$hash) {
        warn "Warning: No hash in manifest. SHA256 for '$(fname $file)' is:`n    $(compute_hash $file 'sha256')"
        return $true, $null
    }

    Write-Host "Checking hash of " -NoNewline
    Write-Host $(url_remote_filename $url) -f Cyan -NoNewline
    Write-Host " ... " -nonewline
    $type, $expected = $hash.split(':')
    if(!$expected) {
        # no type specified, assume sha256
        $type, $expected = 'sha256', $type
    }

    if(@('md5','sha1','sha256', 'sha512') -notcontains $type) {
        return $false, "Hash type '$type' isn't supported."
    }

    $actual = (compute_hash $file $type).ToLower()
    $expected = $expected.ToLower()

    if($actual -ne $expected) {
        $msg = "Hash check failed!`n"
        $msg += "App:         $app_name`n"
        $msg += "URL:         $url`n"
        if(Test-Path $file) {
            $hexbytes = Get-Content $file -Encoding byte -TotalCount 8 | ForEach-Object { $_.tostring('x2') }
            $hexbytes = [string]::join(' ', $hexbytes).ToUpper()
            $msg += "First bytes: $hexbytes`n"
        }
        if($expected -or $actual) {
            $msg += "Expected:    $expected`n"
            $msg += "Actual:      $actual"
        }
        return $false, $msg
    }
    Write-Host "ok." -f Green
    return $true, $null
}

function compute_hash($file, $algname) {
    try {
        if([bool](Get-Command -Name Get-FileHash -ErrorAction SilentlyContinue) -eq $true) {
            return (Get-FileHash -Path $file -Algorithm $algname).Hash.ToLower()
        } else {
            $fs = [system.io.file]::openread($file)
            $alg = [system.security.cryptography.hashalgorithm]::create($algname)
            $hexbytes = $alg.computehash($fs) | ForEach-Object { $_.tostring('x2') }
            return [string]::join('', $hexbytes)
        }
    } catch {
        error $_.exception.message
    } finally {
        if($fs) { $fs.dispose() }
        if($alg) { $alg.dispose() }
    }
    return ''
}

function cmd_available($cmd) {
    try { Get-Command $cmd -ea stop | out-null } catch { return $false }
    $true
}

# for dealing with installers
function args($config, $dir, $global) {
    if($config) { return $config | ForEach-Object { (format $_ @{'dir'=$dir;'global'=$global}) } }
    @()
}

function run($exe, $arg, $msg, $continue_exit_codes) {
    if($msg) { write-host "$msg " -nonewline }
    try {
        #Allow null/no arguments to be passed
        $parameters = @{ }
        if ($arg)
        {
            $parameters.arg = $arg;
        }

        $proc = start-process $exe -wait -ea stop -passthru @parameters


        if($proc.exitcode -ne 0) {
            if($continue_exit_codes -and ($continue_exit_codes.containskey($proc.exitcode))) {
                warn $continue_exit_codes[$proc.exitcode]
                return $true
            }
            write-host "Exit code was $($proc.exitcode)."; return $false
        }
    } catch {
        write-host -f darkred $_.exception.tostring()
        return $false
    }
    if($msg) { Write-Host "done." -f Green }
    return $true
}

function unpack_inno($fname, $manifest, $dir) {
    if(!$manifest.innosetup) { return }

    write-host "Unpacking innosetup... " -nonewline
    innounp -x -d"$dir\_scoop_unpack" "$dir\$fname" > "$dir\innounp.log"
    if($lastexitcode -ne 0) {
        abort "Failed to unpack innosetup file. See $dir\innounp.log"
    }

    Get-ChildItem "$dir\_scoop_unpack\{app}" -r | Move-Item -dest "$dir" -force

    Remove-Item -r -force "$dir\_scoop_unpack"

    Remove-Item "$dir\$fname"
    Write-Host "done." -f Green
}

function run_installer($fname, $manifest, $architecture, $dir, $global) {
    # MSI or other installer
    $msi = msi $manifest $architecture
    $installer = installer $manifest $architecture
    if($installer.script) {
        write-output "Running installer script..."
        Invoke-Expression (@($installer.script) -join "`r`n")
        return
    }

    if($msi) {
        install_msi $fname $dir $msi
    } elseif($installer) {
        install_prog $fname $dir $installer $global
    }
}

# deprecated (see also msi_installed)
function install_msi($fname, $dir, $msi) {
    $msifile = "$dir\$(coalesce $msi.file "$fname")"
    if(!(is_in_dir $dir $msifile)) {
        abort "Error in manifest: MSI file $msifile is outside the app directory."
    }
    if(!($msi.code)) { abort "Error in manifest: Couldn't find MSI code."}
    if(msi_installed $msi.code) { abort "The MSI package is already installed on this system." }

    $logfile = "$dir\install.log"

    $arg = @("/i `"$msifile`"", '/norestart', "/lvp `"$logfile`"", "TARGETDIR=`"$dir`"",
        "INSTALLDIR=`"$dir`"") + @(args $msi.args $dir)

    if($msi.silent) { $arg += '/qn', 'ALLUSERS=2', 'MSIINSTALLPERUSER=1' }
    else { $arg += '/qb-!' }

    $continue_exit_codes = @{ 3010 = "a restart is required to complete installation" }

    $installed = run 'msiexec' $arg "Running installer..." $continue_exit_codes
    if(!$installed) {
        abort "Installation aborted. You might need to run 'scoop uninstall $app' before trying again."
    }
    Remove-Item $logfile
    Remove-Item $msifile
}

function extract_msi($path, $to) {
    $logfile = "$(split-path $path)\msi.log"
    $ok = run 'msiexec' @('/a', "`"$path`"", '/qn', "TARGETDIR=`"$to`"", "/lwe `"$logfile`"")
    if(!$ok) { abort "Failed to extract files from $path.`nLog file:`n  $(friendly_path $logfile)" }
    if(test-path $logfile) { Remove-Item $logfile }
}

function extract_lessmsi($path, $to) {
    Invoke-Expression "lessmsi x `"$path`" `"$to\`""
}

# deprecated
# get-wmiobject win32_product is slow and checks integrity of each installed program,
# so this uses the [wmi] type accelerator instead
# http://blogs.technet.com/b/heyscriptingguy/archive/2011/12/14/use-powershell-to-find-and-uninstall-software.aspx
function msi_installed($code) {
    $path = "hklm:\software\microsoft\windows\currentversion\uninstall\$code"
    if(!(test-path $path)) { return $false }
    $key = Get-Item $path
    $name = $key.getvalue('displayname')
    $version = $key.getvalue('displayversion')
    $classkey = "IdentifyingNumber=`"$code`",Name=`"$name`",Version=`"$version`""
    try { $wmi = [wmi]"Win32_Product.$classkey"; $true } catch { $false }
}

function install_prog($fname, $dir, $installer, $global) {
    $prog = "$dir\$(coalesce $installer.file "$fname")"
    if(!(is_in_dir $dir $prog)) {
        abort "Error in manifest: Installer $prog is outside the app directory."
    }
    $arg = @(args $installer.args $dir $global)

    if($prog.endswith('.ps1')) {
        & $prog @arg
    } else {
        $installed = run $prog $arg "Running installer..."
        if(!$installed) {
            abort "Installation aborted. You might need to run 'scoop uninstall $app' before trying again."
        }

        # Don't remove installer if "keep" flag is set to true
        if(!($installer.keep -eq "true")) {
            Remove-Item $prog
        }
    }
}

function run_uninstaller($manifest, $architecture, $dir) {
    $msi = msi $manifest $architecture
    $uninstaller = uninstaller $manifest $architecture
    if($uninstaller.script) {
        write-output "Running uninstaller script..."
        Invoke-Expression (@($uninstaller.script) -join "`r`n")
        return
    }

    if($msi -or $uninstaller) {
        $exe = $null; $arg = $null; $continue_exit_codes = @{}

        if($msi) {
            $code = $msi.code
            $exe = "msiexec";
            $arg = @("/norestart", "/x $code")
            if($msi.silent) {
                $arg += '/qn', 'ALLUSERS=2', 'MSIINSTALLPERUSER=1'
            } else {
                $arg += '/qb-!'
            }

            $continue_exit_codes.1605 = 'not installed, skipping'
            $continue_exit_codes.3010 = 'restart required'
        } elseif($uninstaller) {
            $exe = "$dir\$($uninstaller.file)"
            $arg = args $uninstaller.args
            if(!(is_in_dir $dir $exe)) {
                warn "Error in manifest: Installer $exe is outside the app directory, skipping."
                $exe = $null;
            } elseif(!(test-path $exe)) {
                warn "Uninstaller $exe is missing, skipping."
                $exe = $null;
            }
        }

        if($exe) {
            if($exe.endswith('.ps1')) {
                & $exe @arg
            } else {
                $uninstalled = run $exe $arg "Running uninstaller..." $continue_exit_codes
                if(!$uninstalled) { abort "Uninstallation aborted." }
            }
        }
    }
}

# get target, name, arguments for shim
function shim_def($item) {
    if($item -is [array]) { return $item }
    return $item, (strip_ext (fname $item)), $null
}

function create_shims($manifest, $dir, $global, $arch) {
    $shims = @(arch_specific 'bin' $manifest $arch)
    $shims | Where-Object { $_ -ne $null } | ForEach-Object {
        $target, $name, $arg = shim_def $_
        write-output "Creating shim for '$name'."

        if(test-path "$dir\$target" -pathType leaf) {
            $bin = "$dir\$target"
        } elseif(test-path $target -pathType leaf) {
            $bin = $target
        } else {
            $bin = search_in_path $target
        }
        if(!$bin) { abort "Can't shim '$target': File doesn't exist."}

        shim $bin $global $name (substitute $arg @{ '$dir' = $dir; '$original_dir' = $original_dir; '$persist_dir' = $persist_dir})
    }
}

function rm_shim($name, $shimdir) {
    $shim = "$shimdir\$name.ps1"

    if(!(test-path $shim)) { # handle no shim from failed install
        warn "Shim for '$name' is missing. Skipping."
    } else {
        write-output "Removing shim for '$name'."
        Remove-Item $shim
    }

    # other shim types might be present
    '', '.exe', '.shim', '.cmd' | ForEach-Object {
        if(test-path -Path "$shimdir\$name$_" -PathType leaf) {
            Remove-Item "$shimdir\$name$_"
        }
    }
}

function rm_shims($manifest, $global, $arch) {
    $shims = @(arch_specific 'bin' $manifest $arch)

    $shims | Where-Object { $_ -ne $null } | ForEach-Object {
        $target, $name, $null = shim_def $_
        $shimdir = shimdir $global

        rm_shim $name $shimdir
    }
}

# Gets the path for the 'current' directory junction for
# the specified version directory.
function current_dir($versiondir) {
    $parent = split-path $versiondir
    return "$parent\current"
}


# Creates or updates the directory junction for [app]/current,
# pointing to the specified version directory for the app.
#
# Returns the 'current' junction directory if in use, otherwise
# the version directory.
function link_current($versiondir) {
    if(get_config NO_JUNCTIONS) { return $versiondir }

    $currentdir = current_dir $versiondir

    write-host "Linking $(friendly_path $currentdir) => $(friendly_path $versiondir)"

    if($currentdir -eq $versiondir) {
        abort "Error: Version 'current' is not allowed!"
    }

    if(test-path $currentdir) {
        # remove the junction
        attrib -R /L $currentdir
        & "$env:COMSPEC" /c rmdir $currentdir
    }

    & "$env:COMSPEC" /c mklink /j $currentdir $versiondir | out-null
    attrib $currentdir +R /L
    return $currentdir
}

# Removes the directory junction for [app]/current which
# points to the current version directory for the app.
#
# Returns the 'current' junction directory (if it exists),
# otherwise the normal version directory.
function unlink_current($versiondir) {
    if(get_config NO_JUNCTIONS) { return $versiondir }
    $currentdir = current_dir $versiondir

    if(test-path $currentdir) {
        write-host "Unlinking $(friendly_path $currentdir)"

        # remove read-only attribute on link
        attrib $currentdir -R /L

        # remove the junction
        & "$env:COMSPEC" /c "rmdir $currentdir"
        return $currentdir
    }
    return $versiondir
}

# to undo after installers add to path so that scoop manifest can keep track of this instead
function ensure_install_dir_not_in_path($dir, $global) {
    $path = (env 'path' $global)

    $fixed, $removed = find_dir_or_subdir $path "$dir"
    if($removed) {
        $removed | ForEach-Object { "Installer added '$(friendly_path $_)' to path. Removing."}
        env 'path' $global $fixed
    }

    if(!$global) {
        $fixed, $removed = find_dir_or_subdir (env 'path' $true) "$dir"
        if($removed) {
            $removed | ForEach-Object { warn "Installer added '$_' to system path. You might want to remove this manually (requires admin permission)."}
        }
    }
}

function find_dir_or_subdir($path, $dir) {
    $dir = $dir.trimend('\')
    $fixed = @()
    $removed = @()
    $path.split(';') | ForEach-Object {
        if($_) {
            if(($_ -eq $dir) -or ($_ -like "$dir\*")) { $removed += $_ }
            else { $fixed += $_ }
        }
    }
    return [string]::join(';', $fixed), $removed
}

function env_add_path($manifest, $dir, $global) {
    $manifest.env_add_path | Where-Object { $_ } | ForEach-Object {
        $path_dir = join-path $dir $_

        if(!(is_in_dir $dir $path_dir)) {
            abort "Error in manifest: env_add_path '$_' is outside the app directory."
        }
        add_first_in_path $path_dir $global
    }
}

function add_first_in_path($dir, $global) {
    $dir = fullpath $dir

    # future sessions
    $null, $currpath = strip_path (env 'path' $global) $dir
    env 'path' $global "$dir;$currpath"

    # this session
    $null, $env:PATH = strip_path $env:PATH $dir
    $env:PATH = "$dir;$env:PATH"
}

function env_rm_path($manifest, $dir, $global) {
    # remove from path
    $manifest.env_add_path | Where-Object { $_ } | ForEach-Object {
        $path_dir = join-path $dir $_

        remove_from_path $path_dir $global
    }
}

function env_set($manifest, $dir, $global) {
    if($manifest.env_set) {
        $manifest.env_set | Get-Member -member noteproperty | ForEach-Object {
            $name = $_.name;
            $val = format $manifest.env_set.$($_.name) @{ "dir" = $dir }
            env $name $global $val
            Set-Content env:\$name $val
        }
    }
}
function env_rm($manifest, $global) {
    if($manifest.env_set) {
        $manifest.env_set | Get-Member -member noteproperty | ForEach-Object {
            $name = $_.name
            env $name $global $null
            if(test-path env:\$name) { Remove-Item env:\$name }
        }
    }
}

function pre_install($manifest, $arch) {
    $pre_install = arch_specific 'pre_install' $manifest $arch
    if($pre_install) {
        write-output "Running pre-install script..."
        Invoke-Expression (@($pre_install) -join "`r`n")
    }
}

function post_install($manifest, $arch) {
    $post_install = arch_specific 'post_install' $manifest $arch
    if($post_install) {
        write-output "Running post-install script..."
        Invoke-Expression (@($post_install) -join "`r`n")
    }
}

function show_notes($manifest, $dir, $original_dir, $persist_dir) {
    if($manifest.notes) {
        write-output "Notes"
        write-output "-----"
        write-output (wraptext (substitute $manifest.notes @{ '$dir' = $dir; '$original_dir' = $original_dir; '$persist_dir' = $persist_dir}))
    }
}

function all_installed($apps, $global) {
    $apps | Where-Object {
        $app, $null, $null = parse_app $_
        installed $app $global
    }
}

# returns (uninstalled, installed)
function prune_installed($apps, $global) {
    $installed = @(all_installed $apps $global)

    $uninstalled = $apps | Where-Object { $installed -notcontains $_ }

    return @($uninstalled), @($installed)
}

# check whether the app failed to install
function failed($app, $global) {
    $ver = current_version $app $global
    if(!$ver) { return $false }
    $info = install_info $app $ver $global
    if(!$info) { return $true }
    return $false
}

function ensure_none_failed($apps, $global) {
    foreach($app in $apps) {
        if(failed $app $global) {
            abort "'$app' install failed previously. Please uninstall it and try again."
        }
    }
}

function show_suggestions($suggested) {
    $installed_apps = (installed_apps $true) + (installed_apps $false)

    foreach($app in $suggested.keys) {
        $features = $suggested[$app] | get-member -type noteproperty | ForEach-Object { $_.name }
        foreach($feature in $features) {
            $feature_suggestions = $suggested[$app].$feature

            $fulfilled = $false
            foreach($suggestion in $feature_suggestions) {
                $suggested_app, $bucket, $null = parse_app $suggestion

                if($installed_apps -contains $suggested_app) {
                    $fulfilled = $true;
                    break;
                }
            }

            if(!$fulfilled) {
                write-host "'$app' suggests installing '$([string]::join("' or '", $feature_suggestions))'."
            }
        }
    }
}

# Persistent data
function persist_def($persist) {
    if ($persist -is [Array]) {
        $source = $persist[0]
        $target = $persist[1]
    } else {
        $source = $persist
        $target = $null
    }

    if (!$target) {
        $target = fname($source)
    }

    return $source, $target
}

function persist_data($manifest, $original_dir, $persist_dir) {
    $persist = $manifest.persist
    if($persist) {
        $persist_dir = ensure $persist_dir

        if ($persist -is [String]) {
            $persist = @($persist);
        }

        $persist | ForEach-Object {
            $source, $target = persist_def $_

            write-host "Persisting $source"

            # add base paths
            if (is_directory (fullpath "$dir\$source")) {
                $source = New-Object System.IO.DirectoryInfo(fullpath "$dir\$source")
            } else {
                $source = New-Object System.IO.FileInfo(fullpath "$dir\$source")
            }
            $target = New-Object System.IO.FileInfo(fullpath "$persist_dir\$target")
            if(!$target.Extension -and !$source.Exists) {
                $target = New-Object System.IO.DirectoryInfo($target.FullName)
            }

            if (!$target.Exists) {
                # If we do not have data in the store we move the original
                if ($source.Exists) {
                    Move-Item $source $target
                } elseif($target.GetType() -eq [System.IO.DirectoryInfo]) {
                    # if there is no source and it's a directory we create an empty directory
                    ensure $target.FullName | out-null
                }
            } elseif ($source.Exists) {
                # (re)move original (keep a copy)
                Move-Item $source "$source.original"
            }

            # create link
            if (is_directory $target) {
                & "$env:COMSPEC" /c "mklink /j `"$source`" `"$target`"" | out-null
                attrib $source.FullName +R /L
            } else {
                & "$env:COMSPEC" /c "mklink /h `"$source`" `"$target`"" | out-null
            }
        }
    }
}
cmd.exe /c "refreshenv"
