function Optimize-SecurityProtocol {
    # .NET Framework 4.7+ has a default security protocol called 'SystemDefault',
    # which allows the operating system to choose the best protocol to use.
    # If SecurityProtocolType contains 'SystemDefault' (means .NET4.7+ detected)
    # and the value of SecurityProtocol is 'SystemDefault', just do nothing on SecurityProtocol,
    # 'SystemDefault' will use TLS 1.2 if the webrequest requires.
    $isNewerNetFramework = ([System.Enum]::GetNames([System.Net.SecurityProtocolType]) -contains 'SystemDefault')
    $isSystemDefault = ([System.Net.ServicePointManager]::SecurityProtocol.Equals([System.Net.SecurityProtocolType]::SystemDefault))

    # If not, change it to support TLS 1.2
    if (!($isNewerNetFramework -and $isSystemDefault)) {
        # Set to TLS 1.2 (3072), then TLS 1.1 (768), and TLS 1.0 (192). Ssl3 has been superseded,
        # https://docs.microsoft.com/en-us/dotnet/api/system.net.securityprotocoltype?view=netframework-4.5
        [System.Net.ServicePointManager]::SecurityProtocol = 3072 -bor 768 -bor 192
    }
}

function Get-UserAgent() {
    return "Scoop/1.0 (+http://scoop.sh/) PowerShell/$($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor) (Windows NT $([System.Environment]::OSVersion.Version.Major).$([System.Environment]::OSVersion.Version.Minor); $(if($env:PROCESSOR_ARCHITECTURE -eq 'AMD64'){'Win64; x64; '})$(if($env:PROCESSOR_ARCHITEW6432 -eq 'AMD64'){'WOW64; '})$PSEdition)"
}

function Show-DeprecatedWarning {
    <#
    .SYNOPSIS
        Print deprecated warning for functions, which will be deleted in near future.
    .PARAMETER Invocation
        Invocation to identify location of line.
        Just pass $MyInvocation.
    .PARAMETER New
        New command name.
    #>
    param($Invocation, [String] $New)

    warn ('"{0}" will be deprecated. Please change your code/manifest to use "{1}"' -f $Invocation.MyCommand.Name, $New)
    Write-Host "      -> $($Invocation.PSCommandPath):$($Invocation.ScriptLineNumber):$($Invocation.OffsetInLine)" -ForegroundColor DarkGray
}

function load_cfg($file) {
    if(!(Test-Path $file)) {
        return $null
    }

    try {
        return (Get-Content $file -Raw | ConvertFrom-Json -ErrorAction Stop)
    } catch {
        Write-Host "ERROR loading $file`: $($_.exception.message)"
    }
}

function get_config($name, $default) {
    if($null -eq $scoopConfig.$name -and $null -ne $default) {
        return $default
    }
    return $scoopConfig.$name
}

function set_config($name, $value) {
    if($null -eq $scoopConfig -or $scoopConfig.Count -eq 0) {
        ensure (Split-Path -Path $configFile) | Out-Null
        $scoopConfig = New-Object PSObject
        $scoopConfig | Add-Member -MemberType NoteProperty -Name $name -Value $value
    } else {
        if($value -eq [bool]::TrueString -or $value -eq [bool]::FalseString) {
            $value = [System.Convert]::ToBoolean($value)
        }
        if($null -eq $scoopConfig.$name) {
            $scoopConfig | Add-Member -MemberType NoteProperty -Name $name -Value $value
        } else {
            $scoopConfig.$name = $value
        }
    }

    if($null -eq $value) {
        $scoopConfig.PSObject.Properties.Remove($name)
    }

    ConvertTo-Json $scoopConfig | Set-Content $configFile -Encoding ASCII
    return $scoopConfig
}

function setup_proxy() {
    # note: '@' and ':' in password must be escaped, e.g. 'p@ssword' -> p\@ssword'
    $proxy = get_config 'proxy'
    if(!$proxy) {
        return
    }
    try {
        $credentials, $address = $proxy -split '(?<!\\)@'
        if(!$address) {
            $address, $credentials = $credentials, $null # no credentials supplied
        }

        if($address -eq 'none') {
            [net.webrequest]::defaultwebproxy = $null
        } elseif($address -ne 'default') {
            [net.webrequest]::defaultwebproxy = new-object net.webproxy "http://$address"
        }

        if($credentials -eq 'currentuser') {
            [net.webrequest]::defaultwebproxy.credentials = [net.credentialcache]::defaultcredentials
        } elseif($credentials) {
            $username, $password = $credentials -split '(?<!\\):' | ForEach-Object { $_ -replace '\\([@:])','$1' }
            [net.webrequest]::defaultwebproxy.credentials = new-object net.networkcredential($username, $password)
        }
    } catch {
        warn "Failed to use proxy '$proxy': $($_.exception.message)"
    }
}

# helper functions
function coalesce($a, $b) { if($a) { return $a } $b }

function format($str, $hash) {
    $hash.keys | ForEach-Object { set-variable $_ $hash[$_] }
    $executionContext.invokeCommand.expandString($str)
}
function is_admin {
    $admin = [security.principal.windowsbuiltinrole]::administrator
    $id = [security.principal.windowsidentity]::getcurrent()
    ([security.principal.windowsprincipal]($id)).isinrole($admin)
}

# messages
function abort($msg, [int] $exit_code=1) { write-host $msg -f red; exit $exit_code }
function error($msg) { write-host "ERROR $msg" -f darkred }
function warn($msg) {  write-host "WARN  $msg" -f darkyellow }
function info($msg) {  write-host "INFO  $msg" -f darkgray }
function debug($obj) {
    if((get_config 'debug' $false) -ine 'true' -and $env:SCOOP_DEBUG -ine 'true') {
        return
    }

    $prefix = "DEBUG[$(Get-Date -UFormat %s)]"
    $param = $MyInvocation.Line.Replace($MyInvocation.InvocationName, '').Trim()
    $msg = $obj | Out-String -Stream

    if($null -eq $obj -or $null -eq $msg) {
        Write-Host "$prefix $param = " -f DarkCyan -NoNewline
        Write-Host '$null' -f DarkYellow -NoNewline
        Write-Host " -> $($MyInvocation.PSCommandPath):$($MyInvocation.ScriptLineNumber):$($MyInvocation.OffsetInLine)" -f DarkGray
        return
    }

    if($msg.GetType() -eq [System.Object[]]) {
        Write-Host "$prefix $param ($($obj.GetType()))" -f DarkCyan -NoNewline
        Write-Host " -> $($MyInvocation.PSCommandPath):$($MyInvocation.ScriptLineNumber):$($MyInvocation.OffsetInLine)" -f DarkGray
        $msg | Where-Object { ![String]::IsNullOrWhiteSpace($_) } |
            Select-Object -Skip 2 | # Skip headers
            ForEach-Object {
                Write-Host "$prefix $param.$($_)" -f DarkCyan
            }
    } else {
        Write-Host "$prefix $param = $($msg.Trim())" -f DarkCyan -NoNewline
        Write-Host " -> $($MyInvocation.PSCommandPath):$($MyInvocation.ScriptLineNumber):$($MyInvocation.OffsetInLine)" -f DarkGray
    }
}
function success($msg) { write-host $msg -f darkgreen }

function filesize($length) {
    $gb = [math]::pow(2, 30)
    $mb = [math]::pow(2, 20)
    $kb = [math]::pow(2, 10)

    if($length -gt $gb) {
        "{0:n1} GB" -f ($length / $gb)
    } elseif($length -gt $mb) {
        "{0:n1} MB" -f ($length / $mb)
    } elseif($length -gt $kb) {
        "{0:n1} KB" -f ($length / $kb)
    } else {
        "$($length) B"
    }
}

# dirs
function basedir($global) { if($global) { return $globaldir } $scoopdir }
function appsdir($global) { "$(basedir $global)\apps" }
function shimdir($global) { "$(basedir $global)\shims" }
function appdir($app, $global) { "$(appsdir $global)\$app" }
function versiondir($app, $version, $global) { "$(appdir $app $global)\$version" }
function persistdir($app, $global) { "$(basedir $global)\persist\$app" }
function usermanifestsdir { "$(basedir)\workspace" }
function usermanifest($app) { "$(usermanifestsdir)\$app.json" }
function cache_path($app, $version, $url) {
    $filename = "$app#$version#$url"
    if ($filename.Length -ge 260) {
        $url = $url -replace '\?.*', ''
        $filename = "$app#$version#$url"
        if ($filename.Length -ge 260) {
            $filename = "$app#$version#$(Split-Path $url -leaf)"
        }
    }
    $filename = $filename -replace '[^\w\.\-\#]+', '_'
    $path = Join-Path $SCOOP_CACHE_DIRECTORY $filename
    return $path
}

# apps
function sanitary_path($path) { return [regex]::replace($path, "[/\\?:*<>|]", "") }
function installed($app, $global=$null) {
    if($null -eq $global) { return (installed $app $true) -or (installed $app $false) }
    # Dependencies of the format "bucket/dependency" install in a directory of form
    # "dependency". So we need to extract the bucket from the name and only give the app
    # name to is_directory
    $app = $app.split("/")[-1]
    return is_directory (appdir $app $global)
}
function installed_apps($global) {
    $dir = appsdir $global
    if(test-path $dir) {
        Get-ChildItem $dir | Where-Object { $_.psiscontainer -and $_.name -ne 'scoop' } | ForEach-Object { $_.name }
    }
}

function file_path($app, $file) {
    Show-DeprecatedWarning $MyInvocation 'Get-AppFilePath'
    Get-AppFilePath -App $app -File $file
}

function Get-AppFilePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [String]
        $App,
        [Parameter(Mandatory = $true, Position = 1)]
        [String]
        $File
    )

    # normal path to file
    $Path = "$(versiondir $App 'current' $false)\$File"
    if(Test-Path $Path) {
        return $Path
    }

    # global path to file
    $Path = "$(versiondir $App 'current' $true)\$File"
    if(Test-Path $Path) {
        return $Path
    }

    # not found
    return $null
}

Function Test-CommandAvailable {
    param (
        [String]$Name
    )
    Return [Boolean](Get-Command $Name -ErrorAction Ignore)
}

function Get-HelperPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateSet('7zip', 'Lessmsi', 'Innounp', 'Dark', 'Aria2')]
        [String]
        $Helper
    )

    $HelperPath = $null
    switch ($Helper) {
        '7zip' {
            $HelperPath = Get-AppFilePath '7zip' '7z.exe'
            if([String]::IsNullOrEmpty($HelperPath)) {
                $HelperPath = Get-AppFilePath '7zip-zstd' '7z.exe'
            }
        }
        'Lessmsi' { $HelperPath = Get-AppFilePath 'lessmsi' 'lessmsi.exe' }
        'Innounp' { $HelperPath = Get-AppFilePath 'innounp' 'innounp.exe' }
        'Dark' {
            $HelperPath = Get-AppFilePath 'dark' 'dark.exe'
            if([String]::IsNullOrEmpty($HelperPath)) {
                $HelperPath = Get-AppFilePath 'wixtoolset' 'dark.exe'
            }
        }
        'Aria2' { $HelperPath = Get-AppFilePath 'aria2' 'aria2c.exe' }
    }

    return $HelperPath
}

function Test-HelperInstalled {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateSet('7zip', 'Lessmsi', 'Innounp', 'Dark', 'Aria2')]
        [String]
        $Helper
    )

    return ![String]::IsNullOrWhiteSpace((Get-HelperPath -Helper $Helper))
}

function Test-Aria2Enabled {
    return (Test-HelperInstalled -Helper Aria2) -and (get_config 'aria2-enabled' $true)
}

function app_status($app, $global) {
    $status = @{}
    $status.installed = (installed $app $global)
    $status.version = current_version $app $global
    $status.latest_version = $status.version

    $install_info = install_info $app $status.version $global

    $status.failed = (!$install_info -or !$status.version)
    $status.hold = ($install_info.hold -eq $true)

    $manifest = manifest $app $install_info.bucket $install_info.url
    $status.removed = (!$manifest)
    if($manifest.version) {
        $status.latest_version = $manifest.version
    }

    $status.outdated = $false
    if($status.version -and $status.latest_version) {
        $status.outdated = ((compare_versions $status.latest_version $status.version) -gt 0)
    }

    $status.missing_deps = @()
    $deps = @(runtime_deps $manifest) | Where-Object {
        $app, $bucket, $null = parse_app $_
        return !(installed $app)
    }
    if($deps) {
        $status.missing_deps += ,$deps
    }

    return $status
}

function appname_from_url($url) {
    (split-path $url -leaf) -replace '.json$', ''
}

# paths
function fname($path) { split-path $path -leaf }
function strip_ext($fname) { $fname -replace '\.[^\.]*$', '' }
function strip_filename($path) { $path -replace [regex]::escape((fname $path)) }
function strip_fragment($url) { $url -replace (new-object uri $url).fragment }

function url_filename($url) {
    (split-path $url -leaf).split('?') | Select-Object -First 1
}
# Unlike url_filename which can be tricked by appending a
# URL fragment (e.g. #/dl.7z, useful for coercing a local filename),
# this function extracts the original filename from the URL.
function url_remote_filename($url) {
    $uri = (New-Object URI $url)
    $basename = Split-Path $uri.PathAndQuery -Leaf
    If ($basename -match ".*[?=]+([\w._-]+)") {
        $basename = $matches[1]
    }
    If (($basename -notlike "*.*") -or ($basename -match "^[v.\d]+$")) {
        $basename = Split-Path $uri.AbsolutePath -Leaf
    }
    If (($basename -notlike "*.*") -and ($uri.Fragment -ne "")) {
        $basename = $uri.Fragment.Trim('/', '#')
    }
    return $basename
}

function ensure($dir) { if(!(test-path $dir)) { mkdir $dir > $null }; resolve-path $dir }
function fullpath($path) { # should be ~ rooted
    $executionContext.sessionState.path.getUnresolvedProviderPathFromPSPath($path)
}
function relpath($path) { "$($myinvocation.psscriptroot)\$path" } # relative to calling script
function friendly_path($path) {
    $h = (Get-PsProvider 'FileSystem').home; if(!$h.endswith('\')) { $h += '\' }
    if($h -eq '\') { return $path }
    return "$path" -replace ([regex]::escape($h)), "~\"
}
function is_local($path) {
    ($path -notmatch '^https?://') -and (test-path $path)
}

# operations

function run($exe, $arg, $msg, $continue_exit_codes) {
    Show-DeprecatedWarning $MyInvocation 'Invoke-ExternalCommand'
    Invoke-ExternalCommand -FilePath $exe -ArgumentList $arg -Activity $msg -ContinueExitCodes $continue_exit_codes
}

function Invoke-ExternalCommand {
    [CmdletBinding(DefaultParameterSetName = "Default")]
    [OutputType([Boolean])]
    param (
        [Parameter(Mandatory = $true,
                   Position = 0)]
        [Alias("Path")]
        [ValidateNotNullOrEmpty()]
        [String]
        $FilePath,
        [Parameter(Position = 1)]
        [Alias("Args")]
        [String[]]
        $ArgumentList,
        [Parameter(ParameterSetName = "UseShellExecute")]
        [Switch]
        $RunAs,
        [Alias("Msg")]
        [String]
        $Activity,
        [Alias("cec")]
        [Hashtable]
        $ContinueExitCodes,
        [Parameter(ParameterSetName = "Default")]
        [Alias("Log")]
        [String]
        $LogPath
    )
    if ($Activity) {
        Write-Host "$Activity " -NoNewline
    }
    $Process = New-Object System.Diagnostics.Process
    $Process.StartInfo.FileName = $FilePath
    $Process.StartInfo.Arguments = ($ArgumentList | Select-Object -Unique) -join ' '
    $Process.StartInfo.UseShellExecute = $false
    if ($LogPath) {
        if ($FilePath -match '(^|\W)msiexec($|\W)') {
            $Process.StartInfo.Arguments += " /lwe `"$LogPath`""
        } else {
            $Process.StartInfo.RedirectStandardOutput = $true
            $Process.StartInfo.RedirectStandardError = $true
        }
    }
    if ($RunAs) {
        $Process.StartInfo.UseShellExecute = $true
        $Process.StartInfo.Verb = 'RunAs'
    }
    try {
        $Process.Start() | Out-Null
    } catch {
        if ($Activity) {
            Write-Host "error." -ForegroundColor DarkRed
        }
        error $_.Exception.Message
        return $false
    }
    if ($LogPath -and ($FilePath -notmatch '(^|\W)msiexec($|\W)')) {
        Out-File -FilePath $LogPath -Encoding ASCII -Append -InputObject $Process.StandardOutput.ReadToEnd()
    }
    $Process.WaitForExit()
    if ($Process.ExitCode -ne 0) {
        if ($ContinueExitCodes -and ($ContinueExitCodes.ContainsKey($Process.ExitCode))) {
            if ($Activity) {
                Write-Host "done." -ForegroundColor DarkYellow
            }
            warn $ContinueExitCodes[$Process.ExitCode]
            return $true
        } else {
            if ($Activity) {
                Write-Host "error." -ForegroundColor DarkRed
            }
            error "Exit code was $($Process.ExitCode)!"
            return $false
        }
    }
    if ($Activity) {
        Write-Host "done." -ForegroundColor Green
    }
    return $true
}

function dl($url,$to) {
    $wc = New-Object Net.Webclient
    $wc.headers.add('Referer', (strip_filename $url))
    $wc.Headers.Add('User-Agent', (Get-UserAgent))
    $wc.downloadFile($url,$to)
}

function env($name,$global,$val='__get') {
    $target = 'User'; if($global) {$target = 'Machine'}
    if($val -eq '__get') { [environment]::getEnvironmentVariable($name,$target) }
    else { [environment]::setEnvironmentVariable($name,$val,$target) }
}

function isFileLocked([string]$path) {
    $file = New-Object System.IO.FileInfo $path

    if ((Test-Path -Path $path) -eq $false) {
        return $false
    }

    try {
        $stream = $file.Open([System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        if ($stream) {
            $stream.Close()
        }
        return $false
    }
    catch {
        # file is locked by a process.
        return $true
    }
}

function is_directory([String] $path) {
    return (Test-Path $path) -and (Get-Item $path) -is [System.IO.DirectoryInfo]
}

function movedir($from, $to) {
    $from = $from.trimend('\')
    $to = $to.trimend('\')

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo.FileName = 'robocopy.exe'
    $proc.StartInfo.Arguments = "`"$from`" `"$to`" /e /move"
    $proc.StartInfo.RedirectStandardOutput = $true
    $proc.StartInfo.RedirectStandardError = $true
    $proc.StartInfo.UseShellExecute = $false
    $proc.StartInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $proc.Start()
    $out = $proc.StandardOutput.ReadToEnd()
    $proc.WaitForExit()

    if($proc.ExitCode -ge 8) {
        debug $out
        throw "Could not find '$(fname $from)'! (error $($proc.ExitCode))"
    }

    # wait for robocopy to terminate its threads
    1..10 | ForEach-Object {
        if (Test-Path $from) {
            Start-Sleep -Milliseconds 100
        }
    }
}

function get_app_name($path) {
    if ($path -match '([^/\\]+)[/\\]current[/\\]') {
        return $matches[1].tolower()
    }
    return ''
}

function get_app_name_from_ps1_shim($shim_ps1) {
    if (!(Test-Path($shim_ps1))) {
        return ''
    }
    $content = (Get-Content $shim_ps1 -Encoding utf8) -join ' '
    return get_app_name $content
}

function warn_on_overwrite($shim_ps1, $path) {
    if (!(Test-Path($shim_ps1))) {
        return
    }
    $shim_app = get_app_name_from_ps1_shim $shim_ps1
    $path_app = get_app_name $path
    if ($shim_app -eq $path_app) {
        return
    }
    $filename = [System.IO.Path]::GetFileName($path)
    warn "Overwriting shim to $filename installed from $shim_app"
}

function shim($path, $global, $name, $arg) {
    if(!(test-path $path)) { abort "Can't shim '$(fname $path)': couldn't find '$path'." }
    $abs_shimdir = ensure (shimdir $global)
    if(!$name) { $name = strip_ext (fname $path) }

    $shim = "$abs_shimdir\$($name.tolower())"

    warn_on_overwrite "$shim.ps1" $path

    # convert to relative path
    Push-Location $abs_shimdir
    $relative_path = resolve-path -relative $path
    Pop-Location
    $resolved_path = resolve-path $path

    # if $path points to another drive resolve-path prepends .\ which could break shims
    if($relative_path -match "^(.\\[\w]:).*$") {
        write-output "`$path = `"$path`"" | out-file "$shim.ps1" -encoding utf8
    } else {
        # Setting PSScriptRoot in Shim if it is not defined, so the shim doesn't break in PowerShell 2.0
        Write-Output "if (!(Test-Path Variable:PSScriptRoot)) { `$PSScriptRoot = Split-Path `$MyInvocation.MyCommand.Path -Parent }" | Out-File "$shim.ps1" -Encoding utf8
        write-output "`$path = join-path `"`$psscriptroot`" `"$relative_path`"" | out-file "$shim.ps1" -Encoding utf8 -Append
    }

    if($path -match '\.jar$') {
        "if(`$myinvocation.expectingInput) { `$input | & java -jar `$path $arg @args } else { & java -jar `$path $arg @args }" | out-file "$shim.ps1" -encoding utf8 -append
    } else {
        "if(`$myinvocation.expectingInput) { `$input | & `$path $arg @args } else { & `$path $arg @args }" | out-file "$shim.ps1" -encoding utf8 -append
    }

    if($path -match '\.(exe|com)$') {
        # for programs with no awareness of any shell
        Copy-Item (get_shim_path) "$shim.exe" -force
        write-output "path = $resolved_path" | out-file "$shim.shim" -encoding utf8
        if($arg) {
            write-output "args = $arg" | out-file "$shim.shim" -encoding utf8 -append
        }
    } elseif($path -match '\.(bat|cmd)$') {
        # shim .bat, .cmd so they can be used by programs with no awareness of PSH
        "@`"$resolved_path`" $arg %*" | out-file "$shim.cmd" -encoding ascii

        "#!/bin/sh`nMSYS2_ARG_CONV_EXCL=/C cmd.exe /C `"$resolved_path`" $arg `"$@`"" | out-file $shim -encoding ascii
    } elseif($path -match '\.ps1$') {
        # make ps1 accessible from cmd.exe
        "@echo off
setlocal enabledelayedexpansion
set args=%*
:: replace problem characters in arguments
set args=%args:`"='%
set args=%args:(=``(%
set args=%args:)=``)%
set invalid=`"='
if !args! == !invalid! ( set args= )
powershell -noprofile -ex unrestricted `"& '$resolved_path' $arg %args%;exit `$lastexitcode`"" | out-file "$shim.cmd" -encoding ascii

        "#!/bin/sh`npowershell.exe -noprofile -ex unrestricted `"$resolved_path`" $arg `"$@`"" | out-file $shim -encoding ascii
    } elseif($path -match '\.jar$') {
        "@java -jar `"$resolved_path`" $arg %*" | out-file "$shim.cmd" -encoding ascii
        "#!/bin/sh`njava -jar `"$resolved_path`" $arg `"$@`"" | out-file $shim -encoding ascii
    }
}

function get_shim_path() {
    $shim_path = "$(versiondir 'scoop' 'current')\supporting\shimexe\bin\shim.exe"
    $shim_version = get_config 'shim' 'default'
    switch ($shim_version) {
        '71' { $shim_path = "$(versiondir 'scoop' 'current')\supporting\shims\71\shim.exe"; Break }
        'kiennq' { $shim_path = "$(versiondir 'scoop' 'current')\supporting\shims\kiennq\shim.exe"; Break }
        'default' { Break }
        default { warn "Unknown shim version: '$shim_version'" }
    }
    return $shim_path
}

function search_in_path($target) {
    $path = (env 'PATH' $false) + ";" + (env 'PATH' $true)
    foreach($dir in $path.split(';')) {
        if(test-path "$dir\$target" -pathType leaf) {
            return "$dir\$target"
        }
    }
}

function ensure_in_path($dir, $global) {
    $path = env 'PATH' $global
    $dir = fullpath $dir
    if($path -notmatch [regex]::escape($dir)) {
        write-output "Adding $(friendly_path $dir) to $(if($global){'global'}else{'your'}) path."

        env 'PATH' $global "$dir;$path" # for future sessions...
        $env:PATH = "$dir;$env:PATH" # for this session
    }
}

function ensure_architecture($architecture_opt) {
    if(!$architecture_opt) {
        return default_architecture
    }
    $architecture_opt = $architecture_opt.ToString().ToLower()
    switch($architecture_opt) {
        { @('64bit', '64', 'x64', 'amd64', 'x86_64', 'x86-64')  -contains $_ } { return '64bit' }
        { @('32bit', '32', 'x86', 'i386', '386', 'i686')  -contains $_ } { return '32bit' }
        default { throw [System.ArgumentException] "Invalid architecture: '$architecture_opt'"}
    }
}

function Confirm-InstallationStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [String[]]
        $Apps,
        [Switch]
        $Global
    )
    $Installed = @()
    $Apps | Select-Object -Unique | Where-Object { $_.Name -ne 'scoop' } | ForEach-Object {
        $App, $null, $null = parse_app $_
        if ($Global) {
            if (installed $App $true) {
                $Installed += ,@($App, $true)
            } elseif (installed $App $false) {
                error "'$App' isn't installed globally, but it is installed for your account."
                warn "Try again without the --global (or -g) flag instead."
            } else {
                error "'$App' isn't installed."
            }
        } else {
            if(installed $App $false) {
                $Installed += ,@($App, $false)
            } elseif (installed $App $true) {
                error "'$App' isn't installed for your account, but it is installed globally."
                warn "Try again with the --global (or -g) flag instead."
            } else {
                error "'$App' isn't installed."
            }
        }
    }
    return ,$Installed
}

function strip_path($orig_path, $dir) {
    if($null -eq $orig_path) { $orig_path = '' }
    $stripped = [string]::join(';', @( $orig_path.split(';') | Where-Object { $_ -and $_ -ne $dir } ))
    return ($stripped -ne $orig_path), $stripped
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

function remove_from_path($dir, $global) {
    $dir = fullpath $dir

    # future sessions
    $was_in_path, $newpath = strip_path (env 'path' $global) $dir
    if($was_in_path) {
        Write-Output "Removing $(friendly_path $dir) from your path."
        env 'path' $global $newpath
    }

    # current session
    $was_in_path, $newpath = strip_path $env:PATH $dir
    if($was_in_path) { $env:PATH = $newpath }
}

function ensure_scoop_in_path($global) {
    $abs_shimdir = ensure (shimdir $global)
    # be aggressive (b-e-aggressive) and install scoop first in the path
    ensure_in_path $abs_shimdir $global
}

function ensure_robocopy_in_path {
    if(!(Test-CommandAvailable robocopy)) {
        shim "C:\Windows\System32\Robocopy.exe" $false
    }
}

function wraptext($text, $width) {
    if(!$width) { $width = $host.ui.rawui.buffersize.width };
    $width -= 1 # be conservative: doesn't seem to print the last char

    $text -split '\r?\n' | ForEach-Object {
        $line = ''
        $_ -split ' ' | ForEach-Object {
            if($line.length -eq 0) { $line = $_ }
            elseif($line.length + $_.length + 1 -le $width) { $line += " $_" }
            else { $lines += ,$line; $line = $_ }
        }
        $lines += ,$line
    }

    $lines -join "`n"
}

function pluralize($count, $singular, $plural) {
    if($count -eq 1) { $singular } else { $plural }
}

function reset_alias($name, $value) {
    if($existing = get-alias $name -ea ignore | Where-Object { $_.options -match 'readonly' }) {
        if($existing.definition -ne $value) {
            write-host "Alias $name is read-only; can't reset it." -f darkyellow
        }
        return # already set
    }
    if($value -is [scriptblock]) {
        if(!(test-path -path "function:script:$name")) {
            new-item -path function: -name "script:$name" -value $value | out-null
        }
        return
    }

    set-alias $name $value -scope script -option allscope
}

function reset_aliases() {
    # for aliases where there's a local function, re-alias so the function takes precedence
    $aliases = get-alias | Where-Object { $_.options -notmatch 'readonly|allscope' } | ForEach-Object { $_.name }
    get-childitem function: | ForEach-Object {
        $fn = $_.name
        if($aliases -contains $fn) {
            set-alias $fn local:$fn -scope script
        }
    }

    # for dealing with user aliases
    $default_aliases = @{
        'cp' = 'copy-item'
        'echo' = 'write-output'
        'gc' = 'get-content'
        'gci' = 'get-childitem'
        'gcm' = 'get-command'
        'gm' = 'get-member'
        'iex' = 'invoke-expression'
        'ls' = 'get-childitem'
        'mkdir' = { new-item -type directory @args }
        'mv' = 'move-item'
        'rm' = 'remove-item'
        'sc' = 'set-content'
        'select' = 'select-object'
        'sls' = 'select-string'
    }

    # set default aliases
    $default_aliases.keys | ForEach-Object { reset_alias $_ $default_aliases[$_] }
}

# convert list of apps to list of ($app, $global) tuples
function applist($apps, $global) {
    if(!$apps) { return @() }
    return ,@($apps | ForEach-Object { ,@($_, $global) })
}

function parse_app([string] $app) {
    if($app -match '(?:(?<bucket>[a-zA-Z0-9-]+)\/)?(?<app>.*.json$|[a-zA-Z0-9-_.]+)(?:@(?<version>.*))?') {
        return $matches['app'], $matches['bucket'], $matches['version']
    }
    return $app, $null, $null
}

function show_app($app, $bucket, $version) {
    if($bucket) {
        $app = "$bucket/$app"
    }
    if($version) {
        $app = "$app@$version"
    }
    return $app
}

function last_scoop_update() {
    # PowerShell 6 returns an DateTime Object
    $last_update = (scoop config lastupdate)

    if ($null -ne $last_update -and $last_update.GetType() -eq [System.String]) {
        try {
            $last_update = [System.DateTime]::Parse($last_update)
        } catch {
            $last_update = $null
        }
    }
    return $last_update
}

function is_scoop_outdated() {
    $last_update = $(last_scoop_update)
    $now = [System.DateTime]::Now
    if($null -eq $last_update) {
        scoop config lastupdate $now.ToString('o')
        # enforce an update for the first time
        return $true
    }
    return $last_update.AddHours(3) -lt $now.ToLocalTime()
}

function substitute($entity, [Hashtable] $params, [Bool]$regexEscape = $false) {
    if ($entity -is [Array]) {
        return $entity | ForEach-Object { substitute $_ $params $regexEscape}
    } elseif ($entity -is [String]) {
        $params.GetEnumerator() | ForEach-Object {
            if($regexEscape -eq $false -or $null -eq $_.Value) {
                $entity = $entity.Replace($_.Name, $_.Value)
            } else {
                $entity = $entity.Replace($_.Name, [Regex]::Escape($_.Value))
            }
        }
        return $entity
    }
}

function format_hash([String] $hash) {
    $hash = $hash.toLower()
    switch ($hash.Length)
    {
        32 { $hash = "md5:$hash" } # md5
        40 { $hash = "sha1:$hash" } # sha1
        64 { $hash = $hash } # sha256
        128 { $hash = "sha512:$hash" } # sha512
        default { $hash = $null }
    }
    return $hash
}

function format_hash_aria2([String] $hash) {
    $hash = $hash -split ':' | Select-Object -Last 1
    switch ($hash.Length)
    {
        32 { $hash = "md5=$hash" } # md5
        40 { $hash = "sha-1=$hash" } # sha1
        64 { $hash = "sha-256=$hash" } # sha256
        128 { $hash = "sha-512=$hash" } # sha512
        default { $hash = $null }
    }
    return $hash
}

function get_hash([String] $multihash) {
    $type, $hash = $multihash -split ':'
    if(!$hash) {
        # no type specified, assume sha256
        $type, $hash = 'sha256', $multihash
    }

    if(@('md5','sha1','sha256', 'sha512') -notcontains $type) {
        return $null, "Hash type '$type' isn't supported."
    }

    return $type, $hash.ToLower()
}

function handle_special_urls($url)
{
    # FossHub.com
    if ($url -match "^(?:.*fosshub.com\/)(?<name>.*)(?:\/|\?dwl=)(?<filename>.*)$") {
        $Body = @{
            projectUri      = $Matches.name;
            fileName        = $Matches.filename;
            source          = 'CF';
            isLatestVersion = $true
        }
        if ((Invoke-RestMethod -Uri $url) -match '"p":"(?<pid>[a-f0-9]{24}).*?"r":"(?<rid>[a-f0-9]{24})') {
            $Body.Add("projectId", $Matches.pid)
            $Body.Add("releaseId", $Matches.rid)
        }
        $url = Invoke-RestMethod -Method Post -Uri "https://api.fosshub.com/download/" -ContentType "application/json" -Body (ConvertTo-Json $Body -Compress)
        if ($null -eq $url.error) {
            $url = $url.data.url
        }
    }

    # Sourceforge.net
    if ($url -match "(?:downloads\.)?sourceforge.net\/projects?\/(?<project>[^\/]+)\/(?:files\/)?(?<file>.*?)(?:$|\/download|\?)") {
        # Reshapes the URL to avoid redirections
        $url = "https://downloads.sourceforge.net/project/$($matches['project'])/$($matches['file'])"
    }
    return $url
}

function get_magic_bytes($file) {
    if(!(Test-Path $file)) {
        return ''
    }

    if((Get-Command Get-Content).parameters.ContainsKey('AsByteStream')) {
        # PowerShell Core (6.0+) '-Encoding byte' is replaced by '-AsByteStream'
        return Get-Content $file -AsByteStream -TotalCount 8
    }
    else {
        return Get-Content $file -Encoding byte -TotalCount 8
    }
}

function get_magic_bytes_pretty($file, $glue = ' ') {
    if(!(Test-Path $file)) {
        return ''
    }

    return (get_magic_bytes $file | ForEach-Object { $_.ToString('x2') }) -join $glue
}

##################
# Core Bootstrap #
##################

# Note: Github disabled TLS 1.0 support on 2018-02-23. Need to enable TLS 1.2
#       for all communication with api.github.com
Optimize-SecurityProtocol

# Scoop root directory
$scoopdir = $env:SCOOP, (get_config 'rootPath'), "$env:USERPROFILE\scoop" | Where-Object { -not [String]::IsNullOrEmpty($_) } | Select-Object -First 1

# Scoop global apps directory
$globaldir = $env:SCOOP_GLOBAL, (get_config 'globalPath'), "$env:ProgramData\scoop" | Where-Object { -not [String]::IsNullOrEmpty($_) } | Select-Object -first 1

# Scoop cache directory
# Note: Setting the SCOOP_CACHE environment variable to use a shared directory
#       is experimental and untested. There may be concurrency issues when
#       multiple users write and access cached files at the same time.
#       Use at your own risk.
$cachedir = $env:SCOOP_CACHE, (get_config 'cachePath'), "$scoopdir\cache" | Where-Object { -not [String]::IsNullOrEmpty($_) } | Select-Object -first 1

# Scoop config file migration
$configHome = $env:XDG_CONFIG_HOME, "$env:USERPROFILE\.config" | Select-Object -First 1
$configFile = "$configHome\scoop\config.json"
if ((Test-Path "$env:USERPROFILE\.scoop") -and !(Test-Path $configFile)) {
    New-Item -ItemType Directory (Split-Path -Path $configFile) -ErrorAction Ignore | Out-Null
    Move-Item "$env:USERPROFILE\.scoop" $configFile
    write-host "WARN  Scoop configuration has been migrated from '~/.scoop'" -f darkyellow
    write-host "WARN  to '$configFile'" -f darkyellow
}

# Load Scoop config
$scoopConfig = load_cfg $configFile

# Setup proxy globally
setup_proxy
