# Trime (同文输入法) on an e-ink device

Trime is a Rime front-end: ~8.6 MB, no network permission, no ads, and a native
engine that stays out of memory when idle. Its stock themes are colourful and its
stock schemas do **not** include double pinyin (双拼) — both need work.

## Install

```bash
# pick the APK matching ro.product.cpu.abi
adb push trime-armeabi-v7a.apk /data/local/tmp/trime.apk
adb shell pm install -r -g /data/local/tmp/trime.apk
adb shell ime enable com.osfans.trime/.ime.core.TrimeInputMethodService
adb shell ime set    com.osfans.trime/.ime.core.TrimeInputMethodService
```

The service component is `com.osfans.trime/.ime.core.TrimeInputMethodService`; the
settings activity is reachable through `com.osfans.trime/.MainLauncherAlias`.

## Where Rime data lives — this is the trap

The first-run wizard offers two storage modes. Only one is scriptable:

- **external data directory** (recommended) — pick `rime/` inside
  `Android/data/com.osfans.trime/files/`. That path is writable over ADB, so schemas
  and themes can be pushed. Reach it in the picker via the drawer →
  the "同文输入法" root → `rime`.
- **app-private storage** — `/data/data/com.osfans.trime/files/rime`, unreadable and
  unwritable without root. Choose this and every customisation must be done by hand
  in the UI.

The chosen directory is not just a sync source: Trime uses it as its live Rime user
directory, so `build/` and `user.yaml` appear there.

## Adding a schema

Trime 3.3.12 ships `luna_pinyin*` and `stroke` only. Double pinyin lives in the
Rime `rime-double-pinyin` project:

```bash
RIME=/sdcard/Android/data/com.osfans.trime/files/rime
adb push double_pinyin_mspy.schema.yaml      $RIME/   # 微软双拼
adb push double_pinyin_mspy.custom.yaml      $RIME/   # force simplified output
adb push default.custom.yaml                 $RIME/   # schema_list order
adb shell am force-stop com.osfans.trime
```

`default.custom.yaml`:

```yaml
patch:
  schema_list:
    - schema: double_pinyin_mspy
    - schema: luna_pinyin_simp
    - schema: luna_pinyin
```

`double_pinyin_mspy.custom.yaml`:

```yaml
patch:
  "switches/@2/reset": 1     # switches order: ascii_mode, full_shape, simplification, ascii_punct
```

Then deploy (键盘样式 page or the ↻ button) and check the log:

```bash
adb logcat -d | grep -E "updating schemas|double_pinyin_mspy"
# finished updating schemas: 4 success, 0 failure
```

Verify typing: the pre-edit area shows decoded pinyin ("ni hk" → 你好) and the space
bar shows the schema name.

## Selecting the default schema

Trime remembers the last schema in `user.yaml`. Write it directly to skip the tap:

```yaml
var:
  last_build_time: 1792907496
  previously_selected_schema: double_pinyin_mspy
  schema_access_time:
    double_pinyin_mspy: 1792907496
```

## Making it black and white

Trime themes are `*.trime.yaml` files in the Rime user directory; **the file name is
the theme name shown in 键盘样式 → 主题**. Keyboard colours are not defined in the
`style:` block at all — Trime derives them from the active entry of
`preset_color_schemes` through its `fallback_colors` map (`key_back_color: back_color`,
`hilited_key_back_color: hilited_candidate_back_color`, …).

That is why editing the current scheme is not enough: a user switching schemes, or a
theme update, brings colour back. The bundled `纯黑白.trime.yaml` rewrites **all**
schemes to greyscale.

Regenerate it for another Trime build:

```bash
python scripts/build-trime-bw-theme.py --apk trime.apk --out 纯黑白.trime.yaml
```

The script:

1. extracts `assets/shared/trime.yaml` from the APK (the complete reference theme),
2. replaces colour-defining keys inside `style:` with monochrome values
   (`keyboard_back_color`, `key_back_color`, `key_text_color`, `key_border_color`,
   `shadow_color`, `round_corner`, font sizes),
3. walks `preset_color_schemes` and rewrites every `*_color` value: white/black
   backgrounds, black text, inverted highlight, grey comments.

Deploy, select it, then confirm on screen. To iterate without touching the UI, edit
the file, `adb push` it back and `adb shell am force-stop com.osfans.trime` — the
IME reloads the selected theme on start.

## Installing the theme on a device that already has Trime

```bash
adb push "纯黑白.trime.yaml" /sdcard/Android/data/com.osfans.trime/files/rime/
# then 键盘样式 → 主题 → 纯黑白
```

If the file lands as `纯黑白.trime.yam`, the push truncated the extension — rename on
device (`adb shell mv`). Always `ls -l` after a push.

## Pitfalls

- **`enabled_input_methods`** keeps the disabled IME listed and the system keeps
  trying to bind it. Rewrite it with a single component after disabling.
- Force-stopping an IME is safe; it rebinds on the next focus. It is the fastest way
  to apply a theme or config change.
- On Android 8.1 the default IME can silently revert to a preinstalled one; re-run
  `ime set` after any reboot-level change and verify with `settings get secure
  default_input_method`.
