# Package triage for Android e-ink devices

A package is a candidate for `pm disable-user` when disabling it removes an
advertisement surface, an updater, or a duplicate app the user does not use — and
nothing on the boot path depends on it.

> **Scope: system packages only.** The input to this table is
> `adb shell pm list packages -s`. Anything that shows up in
> `adb shell pm list packages -3` was installed by the user and is never a target,
> no matter how "bloaty" it looks. `scripts/eink-adb.ps1 disable` enforces this and
> refuses non-system packages unless you pass `-IncludeUserApps`.

## Never disable

| Category | Packages | Why |
|---|---|---|
| System UI | `com.android.systemui` | No status bar / nav bar |
| Settings | `com.android.settings`, vendor settings (`com.mgs.settings`, `com.boox.*`) | You lose the settings app |
| Providers | `com.android.providers.*`, `com.android.externalstorage`, `com.android.defcontainer`, `com.android.documentsui` | Storage, downloads, package install all break |
| Installer | `com.android.packageinstaller` | Cannot install APKs anymore |
| WebView | `com.android.webview`, `com.google.android.webview` | Apps crash on launch |
| Bluetooth / telephony | `com.android.bluetooth*`, `providers.telephony` | Hardware services, often referenced by the framework |
| Keyguard / input | `com.android.keychain`, `com.android.inputdevices`, `com.android.location.fused` | subtle, but framework-level |
| Shell / vpn | `com.android.shell`, `com.android.vpndialogs` | adb itself, VPN prompts |

## Usually safe

| Category | Typical packages | Notes |
|---|---|---|
| Vendor app store | `com.moan.appstore`, `com.boox.store`, `com.ireader.store` | Background updater and ad surface |
| Bundled bookstore / reader | `com.duokan.einkreader`, `com.moan.reader`, `com.qidian.*` | Often 50–100 MB; users who read with KOReader/Legado do not need it |
| Office suite | `cn.wps.moffice_eng.lite`, `com.moffice.*` | 10–60 MB |
| Printing | `com.android.bips`, `com.android.printspooler`, `com.android.printservice.recommendation` | Useless without a printer |
| Factory / aging tests | `com.mgs.factorytest`, `com.softwinner.dragonaging`, `com.softwinner.dragonfire`, `*.factorytest`, `*AgingTest*` | Production line tools |
| OTA updaters | `com.abupdate.fota_demo_iot`, `com.softwinner.awmanager`, `com.boox.ota` | ⚠ disables system updates — tell the user |
| Wallpaper | `com.android.wallpaperbackup`, `com.android.wallpapercropper`, `com.android.wallpaper.livepicker` | E-ink has no wallpapers |
| Misc AOSP | `com.android.email`, `com.android.calculator2`, `com.android.musicfx`, `com.svox.pico`, `com.android.htmlviewer`, `com.android.bookmarkprovider` | Individually harmless |
| CTS shims | `com.android.cts.ctsshim`, `com.android.cts.priv.ctsshim` | Certification stubs |
| Boot animation | `com.mas.bootloading`, `*bootanimation*` | Only the splash |
| Stock launcher | `com.moan.launcher`, `com.boox.launcher` | **Only if** the user asked for a new launcher *and* it is already the default home |
| Stock IME | `com.sohu.inputmethod.sogou.oem`, `com.baidu.input*`, `com.iflytek.inputmethod*` | **Only if** the user asked for a new keyboard *and* it already types correctly |

## Reading a name correctly

Chinese vendors often put the real app name only in the APK. `pm list packages` gives
you the package id, not the label. For anything ambiguous, pull the APK — but keep
pulls small: on flaky links, `adb pull` truncates and `zipfile` fails on the result.
If `pyaxmlparser` raises `BadZipFile`, the transfer died; retry or skip the package.

When the label still does not tell you what it does, leave it enabled and tell the
user why. A disabled unknown package is not worth a support call.

## Ordering

Batched debloating is fine on its own — the launcher and IME only matter if those
optional stages were accepted:

1. If a new launcher was requested: install → set home → verify → *then* disable the
   old launcher. If the user said no, the stock launcher is never touched.
2. If a new keyboard was requested: install → enable → verify typing → *then* disable
   the old IME and rewrite `enabled_input_methods` in the same step. If the user said
   no, the stock IME is never touched.
3. Everything else can go in one batch, but verify `dumpsys` and the crash buffer
   immediately afterwards.
