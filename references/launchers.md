# E-ink launchers

All four are installable over ADB, need no root, and run on Android 8+ (`minSdk 26`
or lower). Check `ro.product.cpu.abi` before picking a build.

| Launcher | Package | APK | Language | Best for |
|---|---|---|---|---|
| **InkBoard** | `ai.openduo.inkboard` | ~20 MB | 中文 | 10"+ notes tablets; home grid of 4/8/12/16/24 shortcuts, manual paging, built-in full refresh, file upload over LAN |
| Unlauncher | `com.jkuester.unlauncher` | ~2 MB | English | phone-shaped readers; text list of top apps + searchable drawer |
| inkOS | `app.inkos` | ~6 MB | English | power users; multi-page home, clock styles, widgets, search |
| KISS | `fr.neamar.kiss` | ~3 MB | multi | keyboard-first search launcher; needs a working IME |

## InkBoard

The default recommendation for Chinese e-ink tablets. Pure black and white, no
ripples or inertia, large hit areas, manual page flips instead of scrolling.

```bash
adb push InkBoard-vX.Y.Z.apk /data/local/tmp/launcher.apk
adb shell pm install -r -g /data/local/tmp/launcher.apk
adb shell appops set ai.openduo.inkboard WRITE_SETTINGS allow
adb shell am start -n ai.openduo.inkboard/.MainActivity
adb shell cmd package set-home-activity ai.openduo.inkboard/.MainActivity
adb shell input keyevent KEYCODE_HOME
```

`WRITE_SETTINGS` is only needed for its rotation switch. The launcher's MENU page
also exposes a full-screen refresh ("全刷"), which is the fastest way to clear
ghosting after a theme change.

## Unlauncher

Smallest option and the least code to trust. English-only UI, but the home screen is
just a clock, a date and a list of app names — nothing to localise.

```bash
adb shell cmd package set-home-activity com.jkuester.unlauncher/com.sduduzog.slimlauncher.MainActivity
```

## inkOS

Feature-rich, but upstream only tests Android 10–16. It installs on API 27 and
generally runs, yet it is the one to fall back from if the launcher crashes on a
2018-era device. Verify with a screenshot before disabling the stock launcher.

## Restoring the stock launcher

```bash
adb shell pm enable <stock-launcher-package>
adb shell cmd package set-home-activity <stock-launcher>/<its.MainActivity>
```

Find the component the same way you verified the new one:
`adb shell cmd package query-activities -a android.intent.action.MAIN -c android.intent.category.HOME`.
