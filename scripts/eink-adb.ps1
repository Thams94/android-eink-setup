<#
.SYNOPSIS
  Small ADB helper for Android e-ink devices (Windows).

.DESCRIPTION
  probe, persist, list, disable, enable, install, home, tcp, shot, health.
  Every destructive action is per-package and reversible; nothing here needs root.

.EXAMPLE
  .\eink-adb.ps1 probe

.EXAMPLE
  .\eink-adb.ps1 disable com.moan.appstore com.duokan.einkreader

.EXAMPLE
  .\eink-adb.ps1 enable-file .\disabled-EPD103.txt

.EXAMPLE
  $env:ADB_SERIAL='192.168.50.217:5555'; .\eink-adb.ps1 health
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('probe', 'persist', 'restore-power', 'list', 'disable', 'enable', 'disable-file', 'enable-file', 'install', 'home', 'tcp', 'shot', 'health')]
    [string]$Action = 'probe',

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$Target,

    [string]$Serial = $env:ADB_SERIAL,
    [string]$Adb = $env:ADB,

    # Debloating is a system-app operation. User-installed packages (-3) are refused
    # unless this switch is passed explicitly.
    [switch]$IncludeUserApps
)

$ErrorActionPreference = 'Continue'

function Resolve-Adb {
    if ($Adb) { return $Adb }
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($candidate in @(
            "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
            "$env:ProgramFiles\platform-tools\adb.exe",
            "C:\platform-tools\adb.exe")) {
        if (Test-Path $candidate) { return $candidate }
    }
    throw "adb not found. Pass -Adb <path> or put platform-tools on PATH."
}

$AdbExe = Resolve-Adb

function Invoke-Adb {
    param([string[]]$Arguments, [switch]$Raw)
    $full = @()
    if ($Serial) { $full += @('-s', $Serial) }
    $full += $Arguments
    $out = & $AdbExe @full 2>&1
    if ($Raw) { return $out }
    return ($out | Out-String).Trim()
}

function Assert-Device {
    $state = Invoke-Adb -Arguments @('get-state')
    if ($state -ne 'device') {
        throw "No device in 'device' state (got '$state'). Re-plug the cable, or use: adb connect <ip>:5555"
    }
}

function Get-SystemPackages {
    (Invoke-Adb @('shell', 'pm', 'list', 'packages', '-s')) -split "`n" |
        ForEach-Object { $_.Trim() -replace '^package:', '' } |
        Where-Object { $_ }
}

switch ($Action) {
    'probe' {
        Assert-Device
        "{0,-11}: {1}" -f 'model',   (Invoke-Adb @('shell', 'getprop', 'ro.product.model'))
        "{0,-11}: {1}" -f 'brand',   (Invoke-Adb @('shell', 'getprop', 'ro.product.brand'))
        "{0,-11}: {1}" -f 'android', (Invoke-Adb @('shell', 'getprop', 'ro.build.version.release'))
        "{0,-11}: {1}" -f 'api',     (Invoke-Adb @('shell', 'getprop', 'ro.build.version.sdk'))
        "{0,-11}: {1}" -f 'abi',     (Invoke-Adb @('shell', 'getprop', 'ro.product.cpu.abi'))
        "{0,-11}: {1}" -f 'size',    (Invoke-Adb @('shell', 'wm', 'size'))
        "{0,-11}: {1}" -f 'density', (Invoke-Adb @('shell', 'wm', 'density'))
        "{0,-11}: {1}" -f 'system',  ((Invoke-Adb @('shell', 'pm', 'list', 'packages', '-s') -split "`n").Count)
        "{0,-11}: {1}" -f 'user',    ((Invoke-Adb @('shell', 'pm', 'list', 'packages', '-3') -split "`n").Count)
        "{0,-11}: {1}" -f 'disabled',((Invoke-Adb @('shell', 'pm', 'list', 'packages', '-d') -split "`n").Count)
    }

    'restore-power' {
        # Undo the stay-awake tweaks. On a Doze-less e-ink ROM, skipping this drains
        # a full battery in about a day of idling.
        Assert-Device
        $timeout = if ($Target[0]) { $Target[0] } else { '300000' }
        Invoke-Adb @('shell', 'settings', 'put', 'global', 'stay_on_while_plugged_in', '0') | Out-Null
        Invoke-Adb @('shell', 'settings', 'put', 'system', 'screen_off_timeout', $timeout) | Out-Null
        Invoke-Adb @('shell', 'svc', 'power', 'stayon', 'false') | Out-Null
        "stay_on_while_plugged_in: " + (Invoke-Adb @('shell', 'settings', 'get', 'global', 'stay_on_while_plugged_in'))
        "screen_off_timeout:       " + (Invoke-Adb @('shell', 'settings', 'get', 'system', 'screen_off_timeout'))
        "check: idle one timeout period, then dumpsys power | grep mWakefulness= must read Asleep"
    }

    'persist' {
        Assert-Device
        Invoke-Adb @('shell', 'settings', 'put', 'global', 'stay_on_while_plugged_in', '7') | Out-Null
        Invoke-Adb @('shell', 'settings', 'put', 'system', 'screen_off_timeout', '300000') | Out-Null
        Invoke-Adb @('shell', 'svc', 'power', 'stayon', 'usb') | Out-Null
        "stay-awake: " + (Invoke-Adb @('shell', 'settings', 'get', 'global', 'stay_on_while_plugged_in'))
        "remember: run 'restore-power' when you are done, or the battery will drain"
    }

    'list' {
        Assert-Device
        $model = (Invoke-Adb @('shell', 'getprop', 'ro.product.model')) -replace '[^\w\-]', ''
        if (-not $model) { $model = 'device' }
        $file = Join-Path (Get-Location) "packages-$model.txt"
        (Invoke-Adb @('shell', 'pm', 'list', 'packages', '-s')) -split "`n" |
            ForEach-Object { $_.Trim() -replace '^package:', '' } |
            Where-Object { $_ } | Sort-Object | Set-Content -Encoding UTF8 $file
        "wrote $file"
    }

    'disable' {
        Assert-Device
        $system = Get-SystemPackages
        foreach ($pkg in $Target) {
            if ((-not $IncludeUserApps) -and ($system -notcontains $pkg)) {
                "{0,-48} SKIP (not a system package; pass -IncludeUserApps to override)" -f $pkg
                continue
            }
            "{0,-48} {1}" -f $pkg, (Invoke-Adb @('shell', 'pm', 'disable-user', '--user', '0', $pkg))
        }
    }

    'enable' {
        Assert-Device
        foreach ($pkg in $Target) {
            "{0,-48} {1}" -f $pkg, (Invoke-Adb @('shell', 'pm', 'enable', $pkg))
        }
    }

    'disable-file' {
        Assert-Device
        $file = $Target[0]
        if (-not (Test-Path $file)) { throw "No such file: $file" }
        $system = Get-SystemPackages
        Get-Content $file | Where-Object { $_ -and $_ -notmatch '^\s*#' } | ForEach-Object {
            $pkg = $_.Trim()
            if ((-not $IncludeUserApps) -and ($system -notcontains $pkg)) {
                "{0,-48} SKIP (not a system package; pass -IncludeUserApps to override)" -f $pkg
                return
            }
            "{0,-48} {1}" -f $pkg, (Invoke-Adb @('shell', 'pm', 'disable-user', '--user', '0', $pkg))
        }
    }

    'enable-file' {
        Assert-Device
        $file = $Target[0]
        if (-not (Test-Path $file)) { throw "No such file: $file" }
        Get-Content $file | Where-Object { $_ -and $_ -notmatch '^\s*#' } | ForEach-Object {
            $pkg = $_.Trim()
            "{0,-48} {1}" -f $pkg, (Invoke-Adb @('shell', 'pm', 'enable', $pkg))
        }
    }

    'install' {
        Assert-Device
        $apk = $Target[0]
        if (-not (Test-Path $apk)) { throw "No such APK: $apk" }
        $remote = '/data/local/tmp/' + (Split-Path $apk -Leaf)
        Invoke-Adb @('push', $apk, $remote) | Out-Null
        Invoke-Adb @('shell', 'pm', 'install', '-r', '-g', $remote)
        Invoke-Adb @('shell', 'rm', '-f', $remote) | Out-Null
    }

    'home' {
        Assert-Device
        $component = $Target[0]
        if (-not $component) { throw "Component required, e.g. ai.openduo.inkboard/.MainActivity" }
        Invoke-Adb @('shell', 'cmd', 'package', 'set-home-activity', $component)
        Invoke-Adb @('shell', 'input', 'keyevent', 'KEYCODE_HOME') | Out-Null
        (Invoke-Adb @('shell', 'cmd', 'package', 'resolve-activity', '-a', 'android.intent.action.MAIN', '-c', 'android.intent.category.HOME') -split "`n" |
            Select-String 'packageName=') | ForEach-Object { $_.ToString().Trim() }
    }

    'tcp' {
        Assert-Device
        $ipInfo = Invoke-Adb @('shell', 'ip', '-f', 'inet', 'addr', 'show', 'wlan0')
        $match = [regex]::Match($ipInfo, 'inet (\d+\.\d+\.\d+\.\d+)')
        if (-not $match.Success) { throw "wlan0 has no IPv4 address; join a Wi-Fi network first." }
        $ip = $match.Groups[1].Value
        "device ip: $ip"
        if (-not (Test-Connection -ComputerName $ip -Count 3 -Quiet)) {
            throw "$ip does not answer ping; refusing to move adbd to TCP (you would lose the session)."
        }
        Invoke-Adb @('tcpip', '5555') | Out-Null
        Start-Sleep -Seconds 2
        & $AdbExe connect "$ip`:5555"
        "use: `$env:ADB_SERIAL='$ip`:5555'"
    }

    'shot' {
        Assert-Device
        $name = if ($Target[0]) { $Target[0] } else { 'screenshot.png' }
        Invoke-Adb @('shell', 'screencap', '-p', '/sdcard/_eink_shot.png') | Out-Null
        Invoke-Adb @('pull', '/sdcard/_eink_shot.png', $name) | Out-Null
        Invoke-Adb @('shell', 'rm', '-f', '/sdcard/_eink_shot.png') | Out-Null
        "saved $name"
    }

    'health' {
        Assert-Device
        '-- home --'
        (Invoke-Adb @('shell', 'cmd', 'package', 'resolve-activity', '-a', 'android.intent.action.MAIN', '-c', 'android.intent.category.HOME') -split "`n") |
            Select-String 'packageName=' | ForEach-Object { $_.ToString().Trim() }
        '-- ime --'
        Invoke-Adb @('shell', 'settings', 'get', 'secure', 'default_input_method')
        '-- crash buffer --'
        $crashes = (Invoke-Adb @('logcat', '-d', '-b', 'crash', '-t', '120')) -split "`n" | Select-String 'FATAL|Process:'
        if ($crashes) { $crashes | ForEach-Object { $_.ToString().Trim() } } else { '(empty)' }
    }
}
