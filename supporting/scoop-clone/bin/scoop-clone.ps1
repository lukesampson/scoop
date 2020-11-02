<#
.SYNOPSIS
    Clones a Git repository to target directory
.DESCRIPTION
    A small script that clones a Git repository to target directory with requiring a complete installation of Git
.PARAMETER Repository
    Valid Git repository URL or Path
.PARAMETER Dir
    Target directory where the repository gets cloned to
.EXAMPLE
    PS > .\scoop-clone.ps1 -Repository 'https://github.com/<user>/<repo>/' -Directory '.\test-clone'
#>
param(
    [Parameter(Mandatory)]
    [String] $Repository,
    [Parameter(Mandatory)]
    [String] $Directory
)

Add-Type -TypeDefinition @"
    using System;
    using System.Diagnostics;
    using System.Runtime.InteropServices;

    public static class Kernel32
    {
        [DllImport("kernel32", SetLastError=true, CharSet = CharSet.Ansi)]
        public static extern IntPtr LoadLibrary([MarshalAs(UnmanagedType.LPStr)]string lpFileName);
    }
"@


if([System.IntPtr]::Size -eq 8) {
    [Kernel32]::LoadLibrary((Get-ChildItem "$PSScriptRoot\lib\win32\x64\git2-???????.dll" | Select-Object -First 1).FullName) | Out-Null
} else {
    [Kernel32]::LoadLibrary((Get-ChildItem "$PSScriptRoot\lib\win32\x86\git2-???????.dll" | Select-Object -First 1).FullName) | Out-Null
}

Add-Type -Path "$PSScriptRoot\LibGit2Sharp.dll"

try {
    [LibGit2Sharp.Repository]::Clone($Repository, $Directory)
    exit 0
} catch [Exception] {
    Write-Output $_.Exception.Message
    exit 1
}
