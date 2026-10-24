#!/bin/bash
# Phase 4: audit the connected TV box and save a readable report on the Mac.
# READ-ONLY: only runs getprop / dumpsys / df / pm list style commands.
# Nothing is installed, changed or deleted on the TV box.
#
# Usage:  bash tvbox/tvbox-audit.sh            (uses the only connected device)
#         bash tvbox/tvbox-audit.sh 192.168.1.3:5555


ADB="$(command -v adb || echo "$HOME/Library/Android/sdk/platform-tools/adb")"
[ -x "$ADB" ] || { echo "adb not found. Run tvbox/mac-check.sh first."; exit 1; }

SERIAL_ARGS=()
[ $# -ge 1 ] && SERIAL_ARGS=(-s "$1")

if ! "$ADB" "${SERIAL_ARGS[@]}" get-state 2>/dev/null | grep -q device; then
  echo "No authorised device. Current state:"
  "$ADB" devices -l
  echo "If it says 'unauthorized', accept the 'Allow USB debugging?' prompt on the TV."
  exit 1
fi

sh_() { "$ADB" "${SERIAL_ARGS[@]}" shell "$@" 2>/dev/null | tr -d '\r'; }
prop() { sh_ getprop "$1"; }

OUT_DIR="$HOME/TVBox-Reports"
mkdir -p "$OUT_DIR"
REPORT="$OUT_DIR/tvbox-report-$(date +%Y%m%d-%H%M%S).txt"

{
echo "TV BOX DIAGNOSTIC REPORT  -  $(date)"
echo "==========================================================="

echo; echo "## Connection"
"$ADB" devices -l

echo; echo "## Device"
echo "Manufacturer:     $(prop ro.product.manufacturer)"
echo "Brand / model:    $(prop ro.product.brand) / $(prop ro.product.model)"
echo "Device:           $(prop ro.product.device)"
echo "Android release:  $(prop ro.build.version.release) (SDK $(prop ro.build.version.sdk))"
echo "Security patch:   $(prop ro.build.version.security_patch)"
echo "Build type:       $(prop ro.build.type)"
echo "Fingerprint:      $(prop ro.build.fingerprint)"

echo; echo "## CPU / chipset"
echo "ABIs:             $(prop ro.product.cpu.abilist)"
echo "Board / platform: $(prop ro.product.board) / $(prop ro.board.platform)"
echo "SoC:              $(prop ro.soc.manufacturer) $(prop ro.soc.model)"
echo "Hardware:         $(prop ro.hardware)"
echo "CPU cores:        $(sh_ "grep -c ^processor /proc/cpuinfo")"

echo; echo "## Memory"
sh_ "grep -E 'MemTotal|MemAvailable|SwapTotal|SwapFree' /proc/meminfo"

echo; echo "## Storage"
sh_ df -h /data /sdcard
echo
echo "-- Biggest folders on shared storage (/sdcard)"
sh_ "du -sh /sdcard/* 2>/dev/null | sort -rh | head -15"

echo; echo "## Space used per app (top 25: code + data + cache, bytes)"
sh_ dumpsys diskstats | awk '
  /^Package Names:/ {gsub(/^Package Names: \[|\]$/,""); n=split($0,P,",")}
  /^App Sizes:/     {gsub(/^App Sizes: \[|\]$/,"");     split($0,A,",")}
  /^App Data Sizes:/{gsub(/^App Data Sizes: \[|\]$/,"");split($0,D,",")}
  /^Cache Sizes:/   {gsub(/^Cache Sizes: \[|\]$/,"");   split($0,C,",")}
  END {
    for (i=1;i<=n;i++) {
      gsub(/"/,"",P[i]); t=A[i]+D[i]+C[i]
      printf "%14d  app=%dMB data=%dMB cache=%dMB  %s\n", t, A[i]/1048576, D[i]/1048576, C[i]/1048576, P[i]
    }
  }' | sort -rn | head -25

echo; echo "## Installed third-party apps"
sh_ pm list packages -3 | sed 's/^package:/  /' | sort

echo; echo "## Kodi"
KODI_PKG="$(sh_ pm list packages | sed 's/^package://' | grep -iE 'kodi|xbmc' | head -1)"
if [ -n "$KODI_PKG" ]; then
  echo "Package: $KODI_PKG"
  sh_ dumpsys package "$KODI_PKG" | grep -E 'versionName|versionCode|firstInstallTime|lastUpdateTime' | sort -u
  KODI_HOME="/sdcard/Android/data/$KODI_PKG/files/.kodi"
  echo "Kodi data folder sizes ($KODI_HOME):"
  sh_ "du -sh $KODI_HOME/* $KODI_HOME/userdata/Thumbnails 2>/dev/null"
  echo "Installed add-ons:"
  sh_ "ls $KODI_HOME/addons 2>/dev/null" | sed 's/^/  /'
  echo "(Android 11+ may block reading Android/data over adb; empty lists above can mean 'blocked', not 'empty'.)"
else
  echo "Kodi not installed."
fi

echo; echo "## Recent errors (last 200 lines of error-level log)"
sh_ logcat -d -t 200 '*:E'
} > "$REPORT" 2>&1

echo "Report saved: $REPORT"
open -R "$REPORT" 2>/dev/null || true
