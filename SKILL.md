---
name: android-eink-setup
description: Set up an Android e-ink tablet or reader over ADB — triage and disable built-in bloatware, install an e-ink friendly launcher, and install a Rime/Trime keyboard with a pure black-and-white theme.
whenToUse: Use when an Android e-ink device (Moan/墨案, Boox, iReader, Hisense, Meebook, Duokan, or any Allwinner/Rockchip e-ink board) is connected over ADB and the user wants to strip preinstalled apps, replace the home screen, or install a Chinese IME that renders correctly on e-paper.
---

# Android e-ink device setup

This skill turns a stock Chinese e-ink reader into a calm, low-distraction device:
remove preinstalled bloat, replace the launcher with a monochrome one, and install
a Rime (Trime) keyboard themed for e-paper.

Everything below runs through `adb` only. No root, no flashing, no factory reset.

## Ground rules

1. **Never disable a package the user did not approve.** Present a triaged table and
   let them choose. Disabling the wrong provider package can leave a device that
   cannot install apps or has no home screen.
2. **Record state before mutating it.** Export the package list and the current
   default home/IME first, so every change is reversible (see §7).
3. **Assume the USB link will drop.** On many e-ink boards `adbd` dies after a few
   tens of MB or after the screen sleeps, and `adb devices` shows `offline` while
   the USB device is still enumerated. Switch to Wi-Fi debugging early (§1).
4. **Work in the user's language.** Chinese users expect 中文 output and app names.

## 0. Probe the device

```bash
adb devices -l
adb shell getprop ro.product.model      # EPD103, NoteAir3C, ...
adb shell getprop ro.build.version.release
adb shell getprop ro.build.version.sdk  # API level — decides which tricks are legal
adb shell getprop ro.product.cpu.abi    # armeabi-v7a vs arm64-v8a — picks the APK
adb shell wm size ; adb shell wm density
adb shell pm list packages -3           # already-installed user apps
adb shell pm list packages -s           # system packages (the triage input)
```

Record `ro.product.cpu.abi` before downloading any APK: a 32-bit `armeabi-v7a`
device rejects an arm64-only build at install time.

## 1. Make the link survivable

```bash
adb shell settings put global stay_on_while_plugged_in 7
adb shell settings put system screen_off_timeout 2147483647
adb shell svc power stayon usb
```

If the device drops anyway, move the session to Wi-Fi **once** and keep using that:

```bash
adb shell ip -f inet addr show wlan0 | grep inet      # note the IP
ping -n 3 <IP>                                        # must succeed first!
adb tcpip 5555
adb connect <IP>:5555
adb -s <IP>:5555 shell echo ok
```

Only run `adb tcpip` after the ping succeeds. It moves `adbd` to TCP and drops the
USB ADB interface; if the Wi-Fi path is not reachable you have locked yourself out
until the cable is re-plugged. After a reboot or IP change, reconnect with
`adb connect <new-IP>:5555` — or plug in USB once and repeat.

If `adb devices` says `offline` while the device still appears in Device Manager,
`adbd` is hung; only re-plugging the cable (or a Toggle of USB debugging) revives it.

## 2. Triage the system packages

`references/package-triage.md` holds the full decision table. The short version:

- **Safe to disable** — vendor app stores, bundled bookstores/readers, office suites,
  printing stack (`bips`, `printspooler`, `printservice.recommendation`), factory and
  aging-test apps, OTA updaters, email/calculator/music-effects/TTS/HTML-viewer,
  wallpaper components, CTS shims, boot animation service, the stock launcher, and
  the stock IME (only after a replacement is working).
- **Never disable** — `com.android.systemui`, `settings`, all `providers.*`
  (media/downloads/telephony/settings), `packageinstaller`, `webview`, `bluetooth`,
  `documentsui`, `defcontainer`, `externalstorage`, `keychain`, `storagemanager`,
  `inputdevices`, `fused` location, `ext.services`, `shell`.
- **Ask first** — anything whose name you cannot place. Pull the APK and read its
  label rather than guessing (see below).

Resolve unknown names without root:

```bash
adb shell pm list packages -s -f          # path=package
adb pull /system/app/Foo/Foo.apk          # small APKs only (<5 MB)
python -c "from pyaxmlparser import APK; a=APK('Foo.apk'); print(a.get_package(), a.get_app_name())"
```

## 3. Disable what the user picked

```bash
adb shell pm disable-user --user 0 <package>
adb shell pm list packages -d               # verification
adb shell pm enable <package>               # rollback, per package
```

`pm disable-user` works from the `shell` user on stock ROMs — no root needed. Verify
afterwards that the home screen still resolves and that no crash loop started:

```bash
adb shell cmd package resolve-activity -a android.intent.action.MAIN -c android.intent.category.HOME
adb logcat -d -b crash -t 200 | grep -E "FATAL|Process:"
```

## 4. Install an e-ink launcher

`references/launchers.md` compares InkBoard, Unlauncher, inkOS and KISS. Default
recommendation for a Chinese tablet: **InkBoard** (`ai.openduo.inkboard`) — pure
black-and-white, no animation, large touch targets, manual paging, Chinese UI.

```bash
adb push InkBoard.apk /data/local/tmp/launcher.apk
adb shell pm install -r -g /data/local/tmp/launcher.apk
adb shell appops set ai.openduo.inkboard WRITE_SETTINGS allow   # rotation support
adb shell am start -n ai.openduo.inkboard/.MainActivity         # smoke test
adb shell cmd package set-home-activity ai.openduo.inkboard/.MainActivity
adb shell input keyevent KEYCODE_HOME                           # must land on it
```

Disable the stock launcher **after** the new one is default and visibly working.
Capture a screenshot to confirm, do not trust `set-home-activity` alone:

```bash
adb shell screencap -p /sdcard/s.png && adb pull /sdcard/s.png .
```

## 5. Install the IME and the black-and-white theme

`references/trime.md` has the full walkthrough. Summary:

1. Pick the APK for the device ABI, install, then `ime enable` + `ime set`.
2. Trime's first-run wizard asks where Rime data lives. Choose **external data
   directory** and pick `rime/` under `Android/data/com.osfans.trime/files/` — that
   path is writable over ADB, an app-private dir is not.
3. Push the schema and theme into that directory:

```bash
RIME=/sdcard/Android/data/com.osfans.trime/files/rime
adb push assets/trime/double_pinyin_mspy.schema.yaml $RIME/
adb push assets/trime/default.custom.yaml            $RIME/   # schema_list order
adb push assets/trime/double_pinyin_mspy.custom.yaml $RIME/   # simplified output
adb push "assets/trime/纯黑白.trime.yaml"            $RIME/
```

4. Open Trime → 键盘样式 → 主题 → 纯黑白, then 部署 (the ↻ icon).
5. Force-stop and re-show the keyboard to verify:
   `adb shell am force-stop com.osfans.trime`.
6. Only now disable the stock IME, and repair the enabled-IME list:

```bash
adb shell pm disable-user --user 0 <stock-ime>
adb shell settings put secure enabled_input_methods "com.osfans.trime/.ime.core.TrimeInputMethodService"
adb shell settings put secure default_input_method   "com.osfans.trime/.ime.core.TrimeInputMethodService"
```

### Generating the theme for another Trime version

`assets/trime/纯黑白.trime.yaml` was generated from Trime 3.3.12. For a different
build, regenerate it from the APK instead of hand-editing:

```bash
python scripts/build-trime-bw-theme.py --apk trime.apk --out 纯黑白.trime.yaml
```

The script rewrites every `preset_color_schemes` entry to greyscale and fixes the
style block, so the keyboard cannot fall back to a coloured scheme.

## 6. Verify

```bash
adb shell dumpsys window | grep mCurrentFocus        # launcher actually in front
adb shell dumpsys input_method | grep -E "mCurMethodId|mInputShown"
adb shell pm list packages -d                        # exactly the approved set
adb logcat -d -b crash -t 200                        # must be empty
```

Screenshot the home screen and a keyboard with candidates showing. On a 10.3" e-ink
panel the screenshot is often downscaled for viewing — when tapping by coordinates,
scale from the returned image size to `wm size` (commonly ×1.238 for 1134→1404 px).

## 7. Rollback

Keep a generated script per device: re-enable every package in the same order,
restore the original home component and the original IME, then optionally uninstall
the two added APKs. `scripts/eink-adb.ps1 -Action enable -PackageFile manifest.txt`
and its bash twin do exactly that. Always leave the manifest on disk next to the
report — "what did we disable six months ago" is the question users ask later.

## Reporting

Give the user: the disabled list grouped by purpose, what the new launcher/keyboard
are, the Wi-Fi ADB address, one warning per risky choice (no OTA updates after
disabling the updater; no keyboard if the IME is disabled without a replacement),
and the rollback path.
