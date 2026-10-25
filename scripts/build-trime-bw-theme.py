#!/usr/bin/env python3
"""Build a pure black-and-white Trime theme from a Trime APK.

Trime derives keyboard colours from the active entry of ``preset_color_schemes``
through its ``fallback_colors`` map, so editing only the current scheme brings
colour back as soon as the user switches schemes. This script extracts the
reference theme shipped in the APK and rewrites *every* scheme to greyscale.

Usage:
    python build-trime-bw-theme.py --apk trime.apk --out 纯黑白.trime.yaml

Options:
    --apk       Path to the Trime APK (any recent release).
    --out       Output theme file name. The file name is what Trime shows in
                键盘样式 → 主题, so use the name you want to see on the device.
    --key-size  Override key text size (default: keep source, bumped by --boost).
    --boost     Points added to key/candidate/long-text sizes (default 4).
    --name      Theme name written into ``style.name`` (default 纯黑白).
"""

from __future__ import annotations

import argparse
import io
import re
import sys
import zipfile

THEME_MEMBER = "assets/shared/trime.yaml"

# Keys placed at the top of the ``style:`` block. Values that Trime does not
# recognise are harmless: unknown style keys are ignored.
STYLE_OVERRIDES = [
    ("keyboard_back_color", "0xFFFFFF"),
    ("key_back_color", "0xFFFFFF"),
    ("key_pressed_back_color", "0x000000"),
    ("key_text_color", "0x000000"),
    ("key_pressed_text_color", "0xFFFFFF"),
    ("key_border_color", "0x000000"),
    ("key_symbol_color", "0x333333"),
    ("key_pressed_symbol_color", "0xFFFFFF"),
    ("key_label_color", "0x666666"),
    ("key_pressed_label_color", "0xFFFFFF"),
    ("key_long_text_color", "0x000000"),
    ("shadow_color", "0x00000000"),
    ("round_corner", "0"),
    ("horizontal_gap", "1"),
    ("vertical_gap", "1"),
]

# Per-key size bump. Long-text keys (剪下/複製/貼上) grow more slowly than the main
# glyphs so they stay legible without crowding the key.
SIZE_KEYS = {
    "key_text_size": 4,
    "candidate_text_size": 4,
    "key_long_text_size": 2,
}

COLOR_LINE = re.compile(r"^(\s+)([A-Za-z_]+):\s*(0x[0-9a-fA-F]{6,8})\s*(#.*)?$")


def load_theme(apk_path: str) -> str:
    with zipfile.ZipFile(apk_path) as apk:
        raw = apk.read(THEME_MEMBER)
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        return raw.decode("gbk", errors="replace")


def rewrite_color(key: str, old: str) -> str:
    """Map one scheme colour onto greyscale."""
    if key.startswith("hilited_"):
        if "back_color" in key:
            return "0x000000"
        if "text_color" in key or "symbol_color" in key or "label_color" in key:
            return "0xFFFFFF"
        if "comment" in key:
            return "0xDDDDDD"
        return "0xFFFFFF"
    if key in ("back_color", "candidate_background", "preedit_back_color"):
        return "0xFFFFFF"
    if key in ("border_color", "candidate_separator_color", "shadow_color"):
        return "0x000000"
    if "comment" in key:
        return "0x555555"
    if "text_color" in key or key in ("label_color", "symbol_color", "text_back_color"):
        return "0x000000"
    if "back_color" in key:
        return "0xFFFFFF"
    return old


def patch_style(lines: list[str], name: str, boost: int) -> list[str]:
    start = next(i for i, line in enumerate(lines) if line.startswith("style:"))
    end = start + 1
    while end < len(lines) and (lines[end].startswith((" ", "\t")) or not lines[end].strip()):
        end += 1

    managed = {key for key, _ in STYLE_OVERRIDES} | set(SIZE_KEYS) | {"name"}
    body: list[str] = []
    sizes: dict[str, str] = {}

    for line in lines[start + 1:end]:
        match = re.match(r"^\s{2}([A-Za-z_]+)\s*:\s*(\d+)\s*(?:#.*)?$", line)
        if match and match.group(1) in SIZE_KEYS:
            sizes[match.group(1)] = match.group(2)
        holder = re.match(r"^\s{2}([A-Za-z_]+)\s*:", line)
        if holder and holder.group(1) in managed:
            continue
        body.append(line)
    while body and not body[-1].strip():
        body.pop()

    overrides = [("name", name)] + STYLE_OVERRIDES
    for key, bump in SIZE_KEYS.items():
        if key in sizes:
            step = boost if bump >= 4 else bump
            overrides.append((key, str(int(sizes[key]) + step)))

    block = ["style:"] + [f"  {key}: {value}" for key, value in overrides] + body + [""]
    return lines[:start] + block + lines[end:]


def patch_schemes(lines: list[str]) -> tuple[list[str], int]:
    try:
        start = next(i for i, line in enumerate(lines) if line.startswith("preset_color_schemes:"))
    except StopIteration:
        return lines, 0

    out = lines[: start + 1]
    changed = 0
    for line in lines[start + 1:]:
        match = COLOR_LINE.match(line)
        if not match:
            out.append(line)
            continue
        key, old = match.group(2), match.group(3)
        new = rewrite_color(key, old)
        if new != old:
            changed += 1
        comment = f" {match.group(4)}" if match.group(4) else ""
        out.append(f"{match.group(1)}{key}: {new}{comment}")
    return out, changed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--apk", required=True)
    parser.add_argument("--out", default="纯黑白.trime.yaml")
    parser.add_argument("--name", default="纯黑白")
    parser.add_argument("--boost", type=int, default=4)
    args = parser.parse_args()

    try:
        text = load_theme(args.apk)
    except KeyError:
        print(f"error: {args.apk} does not contain {THEME_MEMBER}", file=sys.stderr)
        return 2

    lines = text.split("\n")
    lines = patch_style(lines, args.name, args.boost)
    lines, changed = patch_schemes(lines)
    body = "\n".join(lines)

    if "preset_keyboards:" not in body or "style:" not in body:
        print("error: extracted theme looks incomplete; aborting", file=sys.stderr)
        return 3

    io.open(args.out, "w", encoding="utf-8", newline="\n").write(body)
    print(f"wrote {args.out}: {len(body)} bytes, {changed} scheme colours rewritten")
    print("next: adb push it into the Trime rime/ directory, then 键盘样式 → 主题")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
