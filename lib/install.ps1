. "$psscriptroot/autoupdate.ps1"
. "$psscriptroot/buckets.ps1"

function nightly_version($date, $quiet = $false) {
    $date_str = $date.tostring("yyyyMMdd")
    if (!$quiet) {
        warn "This is a nightly version. Downloaded files won't be verified."
    }
    "nightly-$date_str"
}

function install_app($app, $architecture, $global, $suggested, $use_cache = $true) {
    $app, $bucket = app $app
    $app, $manifest, $bucket, $url = locate $app $bucket
    $check_hash = $true

    if(!$manifest) {
        abort "Couldn't find manifest for '$app'$(if($url) { " at the URL $url" })."
    }

    $version = $manifest.version
    if(!$version) { abort "Manifest doesn't specify a version." }
    if($version -match '[^\w\.\-_]') {
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

    $fname = dl_urls $app $version $manifest $architecture $dir $use_cache $check_hash
    unpack_inno $fname $manifest $dir
    pre_install $manifest $architecture
    run_installer $fname $manifest $architecture $dir $global $bucket
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

    # env_ensure_home $manifest $global (see comment for env_ensure_home)
    post_install $manifest $architecture

    # save info for uninstall
    save_installed_manifest $app $bucket $dir $url
    save_install_info @{ 'architecture' = $architecture; 'url' = $url; 'bucket' = $bucket } $dir

    if($manifest.suggest) {
        $suggested[$app] = $manifest.suggest
    }

    success "'$app' ($version) was installed successfully!"

    show_notes $manifest $dir $original_dir $persist_dir
}

function locate($app, $bucket) {
    $manifest, $url = $null, $null

    # check if app is a url
    if($app -match '^((ht)|f)tps?://') {
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

    if (!($to -eq $null)) {
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
    $progress = [console]::isoutputredirected -eq $false

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

# download with filesize and progress indicator
function dl($url, $to, $cookies, $progress) {
    $wreq = [net.webrequest]::create($url)
    if($wreq -is [net.httpwebrequest]) {
        $wreq.useragent = 'Scoop/1.0'
        $wreq.referer = strip_filename $url
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

function dl_urls($app, $version, $manifest, $architecture, $dir, $use_cache = $true, $check_hash = $true) {
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

    $data = @{}

    # download first
    foreach($url in $urls) {
        $data.$url = @{
            "fname" = url_filename $url
        }
        $fname = $data.$url.fname

        try {
            dl_with_cache $app $version $url "$dir\$fname" $cookies $use_cache
        } catch {
            write-host -f darkred $_
            abort "URL $url is not valid"
        }
    }

    foreach($url in $urls) {
        $fname = $data.$url.fname

        if($check_hash) {
            $ok, $err = check_hash "$dir\$fname" $url $manifest $architecture
            if(!$ok) {
                # rm cached
                $cached = cache_path $app $version $url
                if(test-path $cached) { rm -force $cached }
                abort $err
            }
        }

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
            write-host "Extracting... " -nonewline
            $null = mkdir "$dir\_tmp"
            & $extract_fn "$dir\$fname" "$dir\_tmp"
            rm "$dir\$fname"
            if ($extract_to) {
                $null = mkdir "$dir\$extract_to" -force
            }
            # fails if zip contains long paths (e.g. atom.json)
            #cp "$dir\_tmp\$extract_dir\*" "$dir\$extract_to" -r -force -ea stop
            movedir "$dir\_tmp\$extract_dir" "$dir\$extract_to"

            if(test-path "$dir\_tmp") { # might have been moved by movedir
                try {
                    rm -r -force "$dir\_tmp" -ea stop
                } catch [system.io.pathtoolongexception] {
                    & "$env:COMSPEC" /c "rmdir /s /q $dir\_tmp"
                } catch [system.unauthorizedaccessexception] {
                    warn "Couldn't remove $dir\_tmp: unauthorized access."
                }
            }

            write-host "done."

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

    $vals = $cookies.psobject.properties | % {
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
    $hashes = @(hash $manifest $arch) | ? { $_ -ne $null };

    if($hashes.length -eq 0) { return $null }

    $urls = @(url $manifest $arch)

    $index = [array]::indexof($urls, $url)
    if($index -eq -1) { abort "Couldn't find hash in manifest for '$url'." }

    @($hashes)[$index]
}

# returns (ok, err)
function check_hash($file, $url, $manifest, $arch) {
    $hash = hash_for_url $manifest $url $arch
    if(!$hash) {
        warn "Warning: No hash in manifest. SHA256 is:`n    $(compute_hash (fullpath $file) 'sha256')"
        return $true
    }

    write-host "Checking hash of $(url_remote_filename $url)... " -nonewline
    $type, $expected = $hash.split(':')
    if(!$expected) {
        # no type specified, assume sha256
        $type, $expected = 'sha256', $type
    }

    if(@('md5','sha1','sha256', 'sha512') -notcontains $type) {
        return $false, "Hash type '$type' isn't supported."
    }

    $actual = compute_hash (fullpath $file) $type

    if($actual -ne $expected) {
        return $false, "Hash check failed for '$url'.`nExpected:`n    $($expected)`nActual:`n    $($actual)"
    }
    write-host "ok."
    return $true
}

function compute_hash($file, $algname) {
    try {
        if([bool](Get-Command -Name Get-FileHash -ErrorAction SilentlyContinue) -eq $true) {
            return (Get-FileHash -Path $file -Algorithm $algname).Hash.ToLower()
        } else {
            $fs = [system.io.file]::openread($file)
            $alg = [system.security.cryptography.hashalgorithm]::create($algname)
            $hexbytes = $alg.computehash($fs) | % { $_.tostring('x2') }
            return [string]::join('', $hexbytes)
        }
    } catch {
        error $_.exception.message
    } finally {
        if($fs) { $fs.dispose() }
        if($alg) { $alg.dispose() }
    }
}

function cmd_available($cmd) {
    try { gcm $cmd -ea stop | out-null } catch { return $false }
    $true
}

# for dealing with installers
function args($config, $dir, $global) {
    if($config) { return $config | % { (format $_ @{'dir'=$dir;'global'=$global}) } }
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
    if($msg) { write-host "done." }
    return $true
}

function unpack_inno($fname, $manifest, $dir) {
    if(!$manifest.innosetup) { return }

    write-host "Unpacking innosetup... " -nonewline
    innounp -x -d"$dir\_scoop_unpack" "$dir\$fname" > "$dir\innounp.log"
    if($lastexitcode -ne 0) {
        abort "Failed to unpack innosetup file. See $dir\innounp.log"
    }

    gci "$dir\_scoop_unpack\{app}" -r | mv -dest "$dir" -force

    rmdir -r -force "$dir\_scoop_unpack"

    rm "$dir\$fname"
    write-host "done."
}

function run_installer($fname, $manifest, $architecture, $dir, $global, $bucket) {
    # MSI or other installer
    $msi = msi $manifest $architecture
    $installer = installer $manifest $architecture
    if($installer.script) {
        write-output "Running installer script..."
        iex $installer.script
        return
    }

    if($installer.bucket_file) {
        install_bucket_prog $fname $dir $installer $global $bucket
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
    rm $logfile
    rm $msifile
}

function extract_msi($path, $to) {
    $logfile = "$(split-path $path)\msi.log"
    $ok = run 'msiexec' @('/a', "`"$path`"", '/qn', "TARGETDIR=`"$to`"", "/lwe `"$logfile`"")
    if(!$ok) { abort "Failed to extract files from $path.`nLog file:`n  $(friendly_path $logfile)" }
    if(test-path $logfile) { rm $logfile }
}

function extract_lessmsi($path, $to) {
    iex "lessmsi x `"$path`" `"$to\`""
}

# deprecated
# get-wmiobject win32_product is slow and checks integrity of each installed program,
# so this uses the [wmi] type accelerator instead
# http://blogs.technet.com/b/heyscriptingguy/archive/2011/12/14/use-powershell-to-find-and-uninstall-software.aspx
function msi_installed($code) {
    $path = "hklm:\software\microsoft\windows\currentversion\uninstall\$code"
    if(!(test-path $path)) { return $false }
    $key = gi $path
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
            rm $prog
        }
    }
}

function install_bucket_prog($fname, $dir, $installer, $global, $bucket) {
    $bucketdir = $(bucketdir $bucket)
    $prog = "$bucketdir\$(coalesce $installer.bucket_file "$fname")"
    if(!(is_in_dir $bucketdir $prog)) {
        abort "Error in manifest: Installer $prog is outside the bucket directory."
    }
    $arg = @(args $installer.args $dir $global)

    if($prog.endswith('.ps1')) {
        & $prog @arg
    } else {
        $installed = run $prog $arg "Running installer..."
        if(!$installed) {
            abort "Installation aborted. You might need to run 'scoop uninstall $app' before trying again."
        }
    }
}

function run_uninstaller($manifest, $architecture, $dir, $bucket) {
    $msi = msi $manifest $architecture
    $uninstaller = uninstaller $manifest $architecture
    if($uninstaller.script) {
        write-output "Running uninstaller script..."
        iex $uninstaller.script
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
            if($uninstaller.bucket_file) {
                $bucketdir = $(bucketdir $bucket)
                $exe = "$bucketdir\$($uninstaller.bucket_file)"
                if(!(is_in_dir $bucketdir $exe)) {
                    warn "Error in manifest: Installer $exe is outside the bucket directory, skipping."
                    $exe = $null;
                }
            } else {
                $exe = "$dir\$($uninstaller.file)"
                if(!(is_in_dir $dir $exe)) {
                    warn "Error in manifest: Installer $exe is outside the app directory, skipping."
                    $exe = $null;
                }
            }
            $arg = args $uninstaller.args
            if($exe -and !(test-path $exe)) {
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
    $shims | ?{ $_ -ne $null } | % {
        $target, $name, $arg = shim_def $_
        write-output "Creating shim for '$name'."

        # check valid bin
        $bin = "$dir\$target"
        if(!(is_in_dir $dir $bin)) {
            abort "Error in manifest: bin '$target' is outside the app directory."
        }
        if(!(test-path $bin)) { abort "Can't shim '$target': File doesn't exist."}

        shim "$dir\$target" $global $name (substitute $arg @{ '$dir' = $dir; '$original_dir' = $original_dir; '$persist_dir' = $persist_dir})
    }
}

function rm_shim($name, $shimdir) {
    $shim = "$shimdir\$name.ps1"

    if(!(test-path $shim)) { # handle no shim from failed install
        warn "Shim for '$name' is missing. Skipping."
    } else {
        write-output "Removing shim for '$name'."
        rm $shim
    }

    # other shim types might be present
    '', '.exe', '.shim', '.cmd' | % {
        if(test-path -Path "$shimdir\$name$_" -PathType leaf) {
            rm "$shimdir\$name$_"
        }
    }
}

function rm_shims($manifest, $global, $arch) {
    $shims = @(arch_specific 'bin' $manifest $arch)

    $shims | ?{ $_ -ne $null } | % {
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
        $removed | % { "Installer added '$(friendly_path $_)' to path. Removing."}
        env 'path' $global $fixed
    }

    if(!$global) {
        $fixed, $removed = find_dir_or_subdir (env 'path' $true) "$dir"
        if($removed) {
            $removed | % { warn "Installer added '$_' to system path. You might want to remove this manually (requires admin permission)."}
        }
    }
}

function find_dir_or_subdir($path, $dir) {
    $dir = $dir.trimend('\')
    $fixed = @()
    $removed = @()
    $path.split(';') | % {
        if($_) {
            if(($_ -eq $dir) -or ($_ -like "$dir\*")) { $removed += $_ }
            else { $fixed += $_ }
        }
    }
    return [string]::join(';', $fixed), $removed
}

function env_add_path($manifest, $dir, $global) {
    $manifest.env_add_path | ? { $_ } | % {
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
    $manifest.env_add_path | ? { $_ } | % {
        $path_dir = join-path $dir $_

        remove_from_path $path_dir $global
    }
}

function env_set($manifest, $dir, $global) {
    if($manifest.env_set) {
        $manifest.env_set | gm -member noteproperty | % {
            $name = $_.name;
            $val = format $manifest.env_set.$($_.name) @{ "dir" = $dir }
            env $name $global $val
            sc env:\$name $val
        }
    }
}
function env_rm($manifest, $global) {
    if($manifest.env_set) {
        $manifest.env_set | gm -member noteproperty | % {
            $name = $_.name
            env $name $global $null
            if(test-path env:\$name) { rm env:\$name }
        }
    }
}

# UNNECESSARY? Re-evaluate after 3-Jun-2017
# Supposedly some MSYS programs require %HOME% to be set, but I can't
# find any examples.
# Shims used to set %HOME% for the session, but this was removed.
# This function remains in case we need to support this functionality again
# (e.g. env_ensure_home in manifests). But if no problems arise by 3-Jun-2017,
# it's probably safe to delete this, and the call to it install_app
function env_ensure_home($manifest, $global) {
    if($manifest.env_ensure_home -eq $true) {
        if($global){
            if(!(env 'HOME' $true)) {
                env 'HOME' $true $env:ALLUSERSPROFILE
                $env:HOME = $env:ALLUSERSPROFILE # current session
            }
        } else {
            if(!(env 'HOME' $false)) {
                env 'HOME' $false $env:USERPROFILE
                $env:HOME = $env:USERPROFILE # current session
            }
        }
    }
}

function pre_install($manifest, $arch) {
    $pre_install = arch_specific 'pre_install' $manifest $arch
    if($pre_install) {
        write-output "Running pre-install script..."
        iex (@($pre_install) -join "`r`n")
    }
}

function post_install($manifest, $arch) {
    $post_install = arch_specific 'post_install' $manifest $arch
    if($post_install) {
        write-output "Running post-install script..."
        iex (@($post_install) -join "`r`n")
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
    $apps | ? {
        $app, $null = app $_
        installed $app $global
    }
}

# returns (uninstalled, installed)
function prune_installed($apps, $global) {
    $installed = @(all_installed $apps $global)

    $uninstalled = $apps | ? { $installed -notcontains $_ }

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
        $features = $suggested[$app] | get-member -type noteproperty |% { $_.name }
        foreach($feature in $features) {
            $feature_suggestions = $suggested[$app].$feature

            $fulfilled = $false
            foreach($suggestion in $feature_suggestions) {
                $suggested_app, $bucket = app $suggestion

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

        $persist | % {
            $source, $target = persist_def $_

            write-host "Persisting $source"

            # add base paths
            $source = New-Object System.IO.FileInfo(fullpath "$dir\$source")
            if(!$source.Extension) {
                $source = New-Object System.IO.DirectoryInfo($source.FullName)
            }
            $target = New-Object System.IO.FileInfo(fullpath "$persist_dir\$target")
            if(!$target.Extension) {
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
