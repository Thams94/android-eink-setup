---
name: android-eink-setup
description: Set up an Android e-ink tablet or reader over ADB — debloat system apps the user picks, then optionally install an e-ink launcher and/or a Rime/Trime keyboard (default full pinyin) with a black-and-white theme.
whenToUse: Use when an Android e-ink device (Moan/墨案, Boox, iReader, Hisense, Meebook, Duokan, or any Allwinner/Rockchip e-ink board) is connected over ADB and the user wants to remove preinstalled system apps, and/or replace the home screen, and/or install a Chinese IME that renders correctly on e-paper.
---

# Android e-ink device setup

Three independent jobs, run in this order:

| Stage | Required? | Who decides |
|---|---|---|
| 1. Debloat system apps | always offered | **the user picks the packages** |
| 2. Install an e-ink launcher | optional | **the user says yes or no** |
| 3. Install a Rime/Trime keyboard | optional | **the user says yes or no** |
| 4. Restore power settings | mandatory | nobody — just do it |

Everything runs through `adb`. No root, no flashing, no factory reset.

Two things this skill must never do: touch a user-installed app, and leave the
device with an infinite screen timeout.

## Ground rules

1. **System packages only.** Triage `adb shell pm list packages -s` and nothing else.
   `pm list packages -3` is user-installed software — the user put it there, and it is
   out of scope even when it looks like bloat. If a package appears in `-3`, skip it.
2. **Never disable a package the user did not approve.** Present a triaged table and
   let them choose. Disabling the wrong provider package leaves a device that cannot
   install apps or has no home screen.
3. **Ask before each optional stage.** "Install a launcher?" and "Install a keyboard?"
   are two separate yes/no questions with a real "no" answer. A "no" means skip the
   stage *entirely* — do not install anything, do not disable the stock launcher or
   the stock IME, and do not leave half-finished state behind.
4. **Record state before mutating it.** Export the package list and the current
   default home/IME first, so every change is reversible (see §6).
5. **Assume the USB link will drop.** On many e-ink boards `adbd` dies after a few
   tens of MB or after the screen sleeps, and `adb devices` shows `offline` while the
   USB device is still enumerated. Switch to Wi-Fi debugging early (§1).
6. **Work in the user's language.** Chinese users expect 中文 output and app names.

## 0. Probe the device

```bash
adb devices -l
adb shell getprop ro.product.model      # EPD103, NoteAir3C, ...
adb shell getprop ro.build.version.release
adb shell getprop ro.build.version.sdk  # API level — decides which tricks are legal
adb shell getprop ro.product.cpu.abi    # armeabi-v7a vs arm64-v8a — picks the APK
adb shell wm size ; adb shell wm density
adb shell pm list packages -s           # the only debloat input
adb shell pm list packages -3           # read-only context; never disable from here
```

Record `ro.product.cpu.abi` before downloading any APK: a 32-bit `armeabi-v7a`
device rejects an arm64-only build at install time.

## 1. Power snapshot — before anything else

Save the current values so §6 can put them back:

```bash
adb shell settings get system screen_off_timeout            # note it, e.g. 600000
adb shell settings get global stay_on_while_plugged_in      # note it, e.g. null
```

Then, only while you need the link alive:

```bash
adb shell settings put global stay_on_while_plugged_in 7
adb shell settings put system screen_off_timeout 300000     # 5 min, NEVER 2147483647
adb shell svc power stayon usb
```

> **Battery trap.** Many Chinese e-ink ROMs ship with Doze disabled
> (`dumpsys deviceidle` → `mDeepEnabled=false`). On those devices the only path to
> CPU suspend is the screen turning off. An infinite `screen_off_timeout` keeps the
> SoC awake around the clock and flattens a full battery in about a day of idling;
> the user experiences it as "it drains without me reading". This is the single
> easiest way to make a device worse than you found it — §6 is not optional.

If the link drops anyway, move the session to Wi-Fi **once** and keep using that:

```bash
adb shell ip -f inet addr show wlan0 | grep inet      # note the IP
ping -n 3 <IP>                                        # must succeed first!
adb tcpip 5555
adb connect <IP>:5555
adb -s <IP>:5555 shell echo ok
```

Only run `adb tcpip` after the ping succeeds: it moves `adbd` to TCP and drops the
USB ADB interface, so an unreachable Wi-Fi path locks you out until a re-plug.

## 2. Debloat — system apps, user's choice

`references/package-triage.md` holds the decision table. Summarised:

- **Safe to disable** — vendor app stores, bundled bookstores/readers, office suites,
  printing stack, factory/aging-test apps, OTA updaters, email/calculator/
  music-effects/TTS/HTML-viewer, wallpaper components, CTS shims, boot animation.
- **Never disable** — `com.android.systemui`, `settings`, all `providers.*`,
  `packageinstaller`, `webview`, `bluetooth`, `documentsui`, `defcontainer`,
  `externalstorage`, `keychain`, `storagemanager`, `inputdevices`, `fused` location,
  `ext.services`, `shell`.
- **Stock launcher / stock IME** — only disable them *inside* stage 2 or 3, after the
  replacement is proven working, and only if that stage was actually requested.
- **Ask first** — anything you cannot place. Read the APK label rather than guessing.

Present the candidates as a table (number, app name, package, effect, risk) and let
the user choose. Never pre-select a package for them.

Resolving unknown names without root:

```bash
adb shell pm list packages -s -f          # path=package
adb pull /system/app/Foo/Foo.apk          # small APKs only (<5 MB)
python -c "from pyaxmlparser import APK; a=APK('Foo.apk'); print(a.get_package(), a.get_app_name())"
```

Apply, then verify:

```bash
adb shell pm disable-user --user 0 <package>
adb shell pm list packages -d
adb shell pm enable <package>               # per-package rollback
adb shell cmd package resolve-activity -a android.intent.action.MAIN -c android.intent.category.HOME
adb shell logcat -d -b crash -t 200 | grep -E "FATAL|Process:"
```

Write the approved package list to a manifest file as you go — §6 needs it.

## 3. Optional: a new launcher — ask first

> **Ask:** "要不要换一个墨水屏桌面？" If the answer is no, skip this whole section:
> keep the stock launcher, install nothing, disable nothing.

`references/launchers.md` compares InkBoard, Unlauncher, inkOS and KISS. Default
recommendation for a Chinese tablet: **InkBoard** (`ai.openduo.inkboard`) — pure
black-and-white, no animation, large touch targets, manual paging, Chinese UI.
Offer the others if the user wants a different trade-off.

```bash
adb push InkBoard.apk /data/local/tmp/launcher.apk
adb shell pm install -r -g /data/local/tmp/launcher.apk
adb shell appops set ai.openduo.inkboard WRITE_SETTINGS allow   # rotation support
adb shell am start -n ai.openduo.inkboard/.MainActivity         # smoke test
adb shell cmd package set-home-activity ai.openduo.inkboard/.MainActivity
adb shell input keyevent KEYCODE_HOME                           # must land on it
```

Only after a screenshot confirms the new home screen, disable the stock launcher —
and only if the user wants it out of the way:

```bash
adb shell screencap -p /sdcard/s.png && adb pull /sdcard/s.png .
adb shell pm disable-user --user 0 <stock-launcher-package>
```

## 4. Optional: a new keyboard — ask first, default full pinyin

> **Ask:** "要不要换一个输入法？" If no, skip: keep the stock IME enabled and do not
> install Trime at all.

When the answer is yes, the default schema is **全拼** (`luna_pinyin_simp` →
`luna_pinyin`). Double pinyin (双拼) is an opt-in variant that lives in
`assets/trime/optional/double-pinyin/` — install it only if the user asks for it.

`references/trime.md` has the full walkthrough. Summary:

1. Pick the APK for the device ABI, install, then `ime enable` + `ime set`.
2. Trime's first-run wizard asks where Rime data lives. Choose **external data
   directory** and pick `rime/` under `Android/data/com.osfans.trime/files/` — that
   path is writable over ADB, an app-private dir is not.
3. Push the config and theme:

```bash
RIME=/sdcard/Android/data/com.osfans.trime/files/rime
adb push assets/trime/default.custom.yaml  $RIME/             # 全拼 schema_list
adb push "assets/trime/纯黑白.trime.yaml"  $RIME/
# only if the user asked for 双拼:
# adb push assets/trime/optional/double-pinyin/*.yaml $RIME/
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

If the stock IME is the only keyboard and the user said no, leave it alone entirely.

### Generating the theme for another Trime version

`assets/trime/纯黑白.trime.yaml` was generated from Trime 3.3.12. For a different
build, regenerate it from the APK instead of hand-editing:

```bash
python scripts/build-trime-bw-theme.py --apk trime.apk --out 纯黑白.trime.yaml
```

## 5. Verify

```bash
adb shell dumpsys window | grep mCurrentFocus        # launcher actually in front
adb shell dumpsys input_method | grep -E "mCurMethodId|mInputShown"
adb shell pm list packages -d                        # exactly the approved set
adb shell logcat -d -b crash -t 200                  # must be empty
```

Take a screenshot of whatever changed. On a 10.3" e-ink panel the screenshot is often
downscaled for viewing — when tapping by coordinates, scale from the returned image
size to `wm size` (commonly ×1.238 for 1134→1404 px).

## 6. Restore power — mandatory

Put the values from §1 back, or at least a safe default:

```bash
adb shell settings put global stay_on_while_plugged_in 0
adb shell settings put system screen_off_timeout 300000
adb shell svc power stayon false
```

Or: `scripts/eink-adb.ps1 restore-power` (bash twin: `./scripts/eink-adb.sh
restore-power`).

Confirm it actually sleeps — idle past the timeout, then:

```bash
adb shell dumpsys power | grep -E "mWakefulness=|mStayOn=|mScreenOffTimeoutSetting="
# must read mWakefulness=Asleep and mStayOn=false
```

Then hand over the rollback manifest: re-enable every disabled package, restore the
original home component and IME, and note whether the launcher/keyboard were skipped.

```bash
scripts/eink-adb.ps1 enable-file manifest.txt
```

## 7. Troubleshooting: "battery drains without me using it"

Ask for the numbers before touching anything — they name the culprit:

```bash
adb shell "dumpsys batterystats --charged | grep -E 'Screen on:|Amount discharged'"
adb shell "dumpsys batterystats --charged | sed -n '/Estimated power use/,/^$/p' | head -12"
adb shell dumpsys power | grep -E "mWakefulness=|mStayOn=|mScreenOffTimeoutSetting="
adb shell dumpsys deviceidle | grep -E "mDeepEnabled|mState="
adb shell "dumpsys alarm | grep -c RTC_WAKEUP"
```

- `Screen on:` ≈ 100 % and `Amount discharged while screen off: 0` → the screen never
  sleeps. Check `screen_off_timeout`; fix with `restore-power`.
- `mDeepEnabled=false` confirms Doze is unavailable, so screen-off is the only
  suspend path — a long timeout is not "a bit wasteful", it is fatal.
- A large `Screen:` figure with small per-uid numbers means panel/SoC time, not an
  app. One `Uid` dwarfing everything points at a specific app.
- Hundreds of `RTC_WAKEUP` alarms point at an app waking the device; a handful is
  normal.

Never "fix" this by disabling more packages.

## Reporting

Say explicitly which stages ran and which the user declined: the approved disable
list grouped by purpose, whether a launcher was installed (and which), whether a
keyboard was installed (and with which schema — 全拼 by default), the restored power
values, and the rollback path.
