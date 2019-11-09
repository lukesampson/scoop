<p align="center">
<!--<img src="scoop.png" alt="Long live Scoop!"/>-->
    <h1 align="center">Scoop</h1>
</p>
<p align="center">
<b><a href="https://github.com/lukesampson/scoop#what-does-scoop-do">Features</a></b>
|
<b><a href="https://github.com/lukesampson/scoop#installation">Installation</a></b>
|
<b><a href="https://github.com/lukesampson/scoop/wiki">Documentation</a></b>
</p>

- - -
<p align="center" >
    <a href="https://github.com/lukesampson/scoop">
        <img src="https://img.shields.io/github/languages/code-size/lukesampson/scoop.svg" alt="Code Size" />
    </a>
    <a href="https://github.com/lukesampson/scoop">
        <img src="https://img.shields.io/github/repo-size/lukesampson/scoop.svg" alt="Repository size" />
    </a>
    <a href="https://ci.appveyor.com/project/lukesampson/scoop">
        <img src="https://ci.appveyor.com/api/projects/status/05foxatmrqo0l788?svg=true" alt="Build Status" />
    </a>
    <a href="https://discord.gg/s9yRQHt">
        <img src="https://img.shields.io/badge/chat-on%20discord-7289DA.svg" alt="Discord Chat" />
    </a>
    <a href="https://gitter.im/lukesampson/scoop">
        <img src="https://badges.gitter.im/lukesampson/scoop.png" alt="Gitter Chat" />
    </a>
    <a href="https://github.com/lukesampson/scoop/blob/master/LICENSE">
        <img src="https://img.shields.io/github/license/lukesampson/scoop.svg" alt="License" />
    </a>
</p>

Scoop is a command-line installer for Windows.

## What does Scoop do?

Scoop installs programs from the command line with a minimal amount of friction. It tries to eliminate things like:

- Permission popup windows
- GUI wizard-style installers
- Path pollution from installing lots of programs
- Unexpected side-effects from installing and uninstalling programs
- The need to find and install dependencies
- The need to perform extra setup steps to get a working program

Scoop is very scriptable, so you can run repeatable setups to get your environment just the way you like, e.g.:

```powershell
scoop install sudo
sudo scoop install 7zip git openssh --global
scoop install aria2 curl grep sed less touch
scoop install python ruby go perl
```

If you've built software that you'd like others to use, Scoop is an alternative to building an installer (e.g. MSI or InnoSetup) — you just need to zip your program and provide a JSON manifest that describes how to install it.

## Requirements

- Windows 7 SP1+ / Windows Server 2008+
- [PowerShell 5](https://aka.ms/wmf5download) (or later, include [PowerShell Core](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-core-on-windows?view=powershell-6)) and [.NET Framework 4.5](https://www.microsoft.com/net/download) (or later)
- PowerShell must be enabled for your user account e.g. `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`

## Installation

Run the following command from your PowerShell to install scoop to its default location (`C:\Users\<user>\scoop`)

```powershell
Invoke-Expression (New-Object System.Net.WebClient).DownloadString('https://get.scoop.sh')

# or shorter
iwr -useb get.scoop.sh | iex
```

Once installed, run `scoop help` for instructions.

The default setup is configured so all user installed programs and Scoop itself live in `C:\Users\<user>\scoop`.
Globally installed programs (`--global`) live in `C:\ProgramData\scoop`.
These settings can be changed through environment variables.

### Install Scoop to a Custom Directory by changing `SCOOP`

```powershell
$env:SCOOP='D:\Applications\Scoop'
[Environment]::SetEnvironmentVariable('SCOOP', $env:SCOOP, 'User')
# run the installer
```

### Configure Scoop to install global programs to a Custom Directory by changing `SCOOP_GLOBAL`

```powershell
$env:SCOOP_GLOBAL='F:\GlobalScoopApps'
[Environment]::SetEnvironmentVariable('SCOOP_GLOBAL', $env:SCOOP_GLOBAL, 'Machine')
# run the installer
```

## [Documentation](https://github.com/lukesampson/scoop/wiki)

## Multi-connection downloads with `aria2`

Scoop can utilize [`aria2`](https://github.com/aria2/aria2) to use multi-connection downloads. Simply install `aria2` through Scoop and it will be used for all downloads afterward.

```powershell
scoop install aria2
```

You can tweak the following `aria2` settings with the `scoop config` command:

- aria2-enabled (default: true)
- [aria2-retry-wait](https://aria2.github.io/manual/en/html/aria2c.html#cmdoption-retry-wait) (default: 2)
- [aria2-split](https://aria2.github.io/manual/en/html/aria2c.html#cmdoption-s) (default: 5)
- [aria2-max-connection-per-server](https://aria2.github.io/manual/en/html/aria2c.html#cmdoption-x) (default: 5)
- [aria2-min-split-size](https://aria2.github.io/manual/en/html/aria2c.html#cmdoption-k) (default: 5M)

## Inspiration

- [Homebrew](http://mxcl.github.io/homebrew/)
- [sub](https://github.com/37signals/sub#readme)

## What sort of apps can Scoop install?

The apps that install best with Scoop are commonly called "portable" apps: i.e. compressed program files that run stand-alone when extracted and don't have side-effects like changing the registry or putting files outside the program directory.

Since installers are common, Scoop supports them too (and their uninstallers).

Scoop is also great at handling single-file programs and Powershell scripts. These don't even need to be compressed. See the [runat](https://github.com/ScoopInstaller/Main/blob/master/bucket/runat.json) package for an example: it's really just a GitHub gist.

### Support this project

If you find Scoop useful and would like to support ongoing development and maintenance, here's how:

- [PayPal](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=DM2SUH9EUXSKJ) (one-time donation)

## Known application buckets

The following buckets are known to scoop:

- [main](https://github.com/ScoopInstaller/Main) - Default bucket for the most common (mostly CLI) apps
- [extras](https://github.com/lukesampson/scoop-extras) - Apps that don't fit the main bucket's [criteria](https://github.com/lukesampson/scoop/wiki/Criteria-for-including-apps-in-the-main-bucket)
- [games](https://github.com/Calinou/scoop-games) - Open source/freeware games and game-related tools
- [nerd-fonts](https://github.com/matthewjberger/scoop-nerd-fonts) -  Nerd Fonts
- [nirsoft](https://github.com/kodybrown/scoop-nirsoft) - A subset of the [250](https://github.com/rasa/scoop-directory/blob/master/by-score.md#MCOfficer_scoop-nirsoft) [Nirsoft](https://nirsoft.net) apps
- [java](https://github.com/ScoopInstaller/Java) - Installers for Oracle Java, OpenJDK, Zulu, ojdkbuild, AdoptOpenJDK, Amazon Corretto, BellSoft Liberica & SapMachine
- [jetbrains](https://github.com/Ash258/Scoop-JetBrains) - Installers for all JetBrains utilities and IDEs
<!-- * [nightlies](https://github.com/ScoopInstaller/Nightlies) - No longer used -->
- [nonportable](https://github.com/oltolm/scoop-nonportable) - Non-portable apps (may require UAC)
- [php](https://github.com/ScoopInstaller/PHP) - Installers for most versions of PHP
- [versions](https://github.com/ScoopInstaller/Versions) - Alternative versions of apps found in other buckets

The main bucket is installed by default. To add any of the other buckets, type:
```
scoop bucket add bucketname
```
For example, to add the extras bucket, type:
```
scoop bucket add extras
```

## Other application buckets

Many other application buckets hosted on Github can be found in the [Scoop Directory](https://github.com/rasa/scoop-directory).
