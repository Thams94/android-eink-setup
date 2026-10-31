#!/usr/bin/env bash
# eink-adb - small ADB helper for Android e-ink devices (macOS / Linux)
#
#   ./eink-adb.sh probe                 device facts + package counts
#   ./eink-adb.sh persist               keep the device awake while plugged in
#   ./eink-adb.sh restore-power [ms]    undo the stay-awake tweaks (default 5 min)
#   ./eink-adb.sh list                  write all packages to packages-<model>.txt
#   ./eink-adb.sh disable pkg [pkg ...]    pm disable-user --user 0
#   ./eink-adb.sh enable  pkg [pkg ...]    pm enable
#   ./eink-adb.sh enable-file manifest  re-enable every package listed in a file
#   ./eink-adb.sh disable-file manifest disable every package listed in a file
#   ./eink-adb.sh install path.apk      install -r -g, then report the component
#   ./eink-adb.sh home component        cmd package set-home-activity
#   ./eink-adb.sh tcp                   switch this session to Wi-Fi debugging
#   ./eink-adb.sh shot name.png         screenshot to the current directory
#   ./eink-adb.sh health                home/IME resolution + crash buffer
#
# Set ADB_SERIAL to target a specific device (serial or ip:5555).
set -euo pipefail

ADB=${ADB:-adb}
SERIAL=${ADB_SERIAL:-}

adb_cmd() {
  if [ -n "$SERIAL" ]; then
    "$ADB" -s "$SERIAL" "$@"
  else
    "$ADB" "$@"
  fi
}

require_device() {
  local state
  state=$(adb_cmd get-state 2>/dev/null || true)
  if [ "$state" != "device" ]; then
    echo "error: no device in 'device' state (got '${state:-none}')" >&2
    echo "hint: re-plug the cable, or 'adb connect <ip>:5555'" >&2
    exit 1
  fi
}

# Debloating is a system-app operation. User-installed packages (-3) are refused
# unless EINK_ALLOW_USER_APPS=1 is exported.
is_system_pkg() {
  adb_cmd shell pm list packages -s | sed 's/^package://' | tr -d '\r' | grep -qx -- "$1"
}

allow_user_apps() { [ "${EINK_ALLOW_USER_APPS:-0}" = "1" ]; }

cmd=${1:-probe}
shift || true

case "$cmd" in
  probe)
    require_device
    model=$(adb_cmd shell getprop ro.product.model | tr -d '\r')
    echo "model      : $model"
    echo "brand      : $(adb_cmd shell getprop ro.product.brand | tr -d '\r')"
    echo "android    : $(adb_cmd shell getprop ro.build.version.release | tr -d '\r') (API $(adb_cmd shell getprop ro.build.version.sdk | tr -d '\r'))"
    echo "abi        : $(adb_cmd shell getprop ro.product.cpu.abi | tr -d '\r')"
    echo "screen     : $(adb_cmd shell wm size | tr -d '\r') @ $(adb_cmd shell wm density | tr -d '\r')"
    echo "system pkgs: $(adb_cmd shell pm list packages -s | wc -l)"
    echo "user pkgs  : $(adb_cmd shell pm list packages -3 | wc -l)"
    echo "disabled   : $(adb_cmd shell pm list packages -d | wc -l)"
    ;;
  persist)
    require_device
    adb_cmd shell settings put global stay_on_while_plugged_in 7
    adb_cmd shell settings put system screen_off_timeout 300000
    adb_cmd shell svc power stayon usb
    echo "stay-awake: $(adb_cmd shell settings get global stay_on_while_plugged_in | tr -d '\r')"
    echo "remember: run 'restore-power' when you are done, or the battery will drain"
    ;;
  restore-power)
    require_device
    timeout=${1:-300000}
    adb_cmd shell settings put global stay_on_while_plugged_in 0
    adb_cmd shell settings put system screen_off_timeout "$timeout"
    adb_cmd shell svc power stayon false
    echo "screen_off_timeout: $(adb_cmd shell settings get system screen_off_timeout | tr -d '\r')"
    echo "check: idle one timeout period, then dumpsys power | grep mWakefulness= must read Asleep"
    ;;
  list)
    require_device
    model=$(adb_cmd shell getprop ro.product.model | tr -d '\r' | tr -cd '[:alnum:]_-')
    out="packages-${model:-device}.txt"
    adb_cmd shell pm list packages -s | sed 's/^package://' | tr -d '\r' | sort > "$out"
    echo "wrote $out ($(wc -l < "$out") system packages)"
    ;;
  disable)
    require_device
    for pkg in "$@"; do
      if ! allow_user_apps && ! is_system_pkg "$pkg"; then
        printf '%-48s %s\n' "$pkg" "SKIP (not a system package; set EINK_ALLOW_USER_APPS=1 to override)"
        continue
      fi
      printf '%-48s %s\n' "$pkg" "$(adb_cmd shell pm disable-user --user 0 "$pkg" | tr -d '\r')"
    done
    ;;
  enable)
    require_device
    for pkg in "$@"; do
      printf '%-48s %s\n' "$pkg" "$(adb_cmd shell pm enable "$pkg" | tr -d '\r')"
    done
    ;;
  disable-file|enable-file)
    require_device
    [ -f "${1:?manifest file required}" ] || { echo "error: no such file: $1" >&2; exit 1; }
    action=${cmd%-file}
    while IFS= read -r pkg; do
      [ -z "$pkg" ] && continue
      case "$pkg" in \#*) continue ;; esac
      if [ "$action" = "disable" ] && ! allow_user_apps && ! is_system_pkg "$pkg"; then
        printf '%-48s %s\n' "$pkg" "SKIP (not a system package; set EINK_ALLOW_USER_APPS=1 to override)"
        continue
      fi
      printf '%-48s %s\n' "$pkg" "$(adb_cmd shell pm "$action" "$pkg" | tr -d '\r')"
    done < "$1"
    ;;
  install)
    require_device
    apk=${1:?apk path required}
    remote=/data/local/tmp/$(basename "$apk")
    adb_cmd push "$apk" "$remote" >/dev/null
    adb_cmd shell pm install -r -g "$remote"
    adb_cmd shell rm -f "$remote"
    ;;
  home)
    require_device
    adb_cmd shell cmd package set-home-activity "${1:?component required, e.g. ai.openduo.inkboard/.MainActivity}"
    adb_cmd shell input keyevent KEYCODE_HOME
    adb_cmd shell "cmd package resolve-activity -a android.intent.action.MAIN -c android.intent.category.HOME | grep packageName"
    ;;
  tcp)
    require_device
    ip=$(adb_cmd shell ip -f inet addr show wlan0 2>/dev/null | tr -d '\r' | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)
    [ -n "$ip" ] || { echo "error: wlan0 has no IPv4 address; connect the device to Wi-Fi first" >&2; exit 1; }
    echo "device ip: $ip"
    if ! ping -c 3 -W 2 "$ip" >/dev/null 2>&1; then
      echo "error: $ip does not answer ping; refusing to move adbd to TCP" >&2
      exit 1
    fi
    adb_cmd tcpip 5555
    sleep 2
    "$ADB" connect "$ip:5555"
    echo "use: ADB_SERIAL=$ip:5555 $0 probe"
    ;;
  shot)
    require_device
    name=${1:-screenshot.png}
    adb_cmd shell screencap -p /sdcard/_eink_shot.png
    adb_cmd pull /sdcard/_eink_shot.png "$name" >/dev/null
    adb_cmd shell rm -f /sdcard/_eink_shot.png
    echo "saved $name"
    ;;
  health)
    require_device
    echo "-- home --"
    adb_cmd shell "cmd package resolve-activity -a android.intent.action.MAIN -c android.intent.category.HOME | grep packageName" | tr -d '\r'
    echo "-- ime --"
    adb_cmd shell settings get secure default_input_method | tr -d '\r'
    adb_cmd shell dumpsys input_method | grep -E "mCurMethodId" | head -1 | tr -d '\r'
    echo "-- crash buffer --"
    adb_cmd logcat -d -b crash -t 120 | grep -E "FATAL|Process:" || echo "(empty)"
    ;;
  *)
    sed -n '2,20p' "$0"
    exit 1
    ;;
esac
