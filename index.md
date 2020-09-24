---
layout: default
---

# Installs in seconds

Make sure [PowerShell 5](https://aka.ms/wmf5download) (or later, include [PowerShell Core](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-core-on-windows?view=powershell-6))
and [.NET Framework 4.5](https://www.microsoft.com/net/download) (or later) are installed. Then run:

```powershell
Invoke-Expression (New-Object System.Net.WebClient).DownloadString('https://get.scoop.sh')

# or shorter
iwr -useb get.scoop.sh | iex
```

**Note:** if you get an error you might need to change the execution policy
(i.e. enable Powershell) with

```powershell
Set-ExecutionPolicy RemoteSigned -scope CurrentUser
```

### Scoop installs the tools you know and love

```shell
scoop install curl
```

<br>

### Get comfortable on the Windows command line

Looking for familiar Unix tools? Tired of Powershell&rsquo;s *Verb-Noun* verbosity? Scoop helps you get the [programs](https://github.com/ScoopInstaller/Main/blob/master/bucket/) you [need](https://github.com/lukesampson/scoop-extras), with a minimal amount of point-and-clicking.

<br>

### Say goodbye to permission pop-ups

Scoop installs programs to your home directory by default. So you don&rsquo;t need admin permissions to install programs, and you won&rsquo;t see UAC popups every time you need to add or remove a program.

<br>

### Scoop reads the README for you

Not sure whether you need 32-bit or 64-bit? Can&rsquo;t remember that command you have to type after you install to get that other thing you need? Scoop has you covered. Just `scoop install` and you&rsquo;ll be ready to work in no time.

<br>

# Demo

<div class='videoWrapper'>
<iframe src='//www.youtube.com/embed/a85QLUJ0Wbs?rel=0' frameborder='0' allowfullscreen>
</iframe>
</div>

<br>
