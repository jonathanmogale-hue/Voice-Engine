#!/bin/bash
# Phase 1 + 2: inspect this Mac and check whether the TV box is reachable.
# READ-ONLY: installs nothing, changes no settings, scans only the one IP you give.
#
# Usage:  bash tvbox/mac-check.sh [TV_BOX_IP]
#         bash tvbox/mac-check.sh 192.168.1.3

TV_IP="${1:-192.168.1.3}"

section() { printf '\n=== %s ===\n' "$1"; }

section "macOS"
sw_vers
echo "CPU architecture: $(uname -m)"
sysctl -n machdep.cpu.brand_string 2>/dev/null

section "Developer tools"
xcode-select -p 2>/dev/null && echo "Xcode command line tools: installed" || echo "Xcode command line tools: NOT installed"
for t in brew git python3 java; do
  printf '%-8s ' "$t:"; command -v "$t" || echo "not found"
done

section "ADB"
ADB="$(command -v adb)"
if [ -z "$ADB" ]; then
  for p in "$HOME/Library/Android/sdk/platform-tools/adb" "$HOME/platform-tools/adb" /opt/homebrew/bin/adb /usr/local/bin/adb; do
    [ -x "$p" ] && ADB="$p" && break
  done
fi
if [ -n "$ADB" ]; then
  echo "adb found: $ADB"
  "$ADB" version
  echo "--- adb devices -l"
  "$ADB" devices -l
else
  echo "adb NOT installed. Options (ask before installing):"
  echo "  brew install --cask android-platform-tools"
  echo "  or download Platform Tools from https://developer.android.com/tools/releases/platform-tools"
fi
echo "--- running adb server processes"
pgrep -fl "adb" || echo "none"
[ -d "$HOME/.android" ] && echo "~/.android exists (adb keys live here; not printed)"

section "USB devices seen by the Mac (looking for the TV box)"
system_profiler SPUSBDataType 2>/dev/null | grep -E "^\s{4,}[A-Za-z].*:$|Vendor ID|Product ID|Manufacturer" | head -60

section "Network"
for ifc in en0 en1; do
  ip="$(ipconfig getifaddr "$ifc" 2>/dev/null)" && echo "$ifc: $ip"
done
echo "Default gateway: $(route -n get default 2>/dev/null | awk '/gateway/ {print $2}')"

section "TV box at $TV_IP (only this one address is probed)"
if ping -c 2 -t 3 "$TV_IP" >/dev/null 2>&1; then
  echo "ping: reachable"
else
  echo "ping: no reply (may still be fine; some boxes ignore ping)"
fi
arp -n "$TV_IP" 2>/dev/null
echo "Checking the standard ADB TCP port 5555 (classic network ADB):"
if nc -z -G 3 "$TV_IP" 5555 2>/dev/null; then
  echo "  5555 OPEN -> network ADB is listening. Next: adb connect $TV_IP:5555"
else
  echo "  5555 closed -> network ADB is not enabled on the box"
fi
echo "Looking for Android 11+ Wireless-debugging services advertised on the network (5 s):"
( dns-sd -B _adb-tls-connect._tcp local. & sleep 5; kill $! ) 2>/dev/null | grep -v "^Browsing" || true

echo
echo "Done. Paste everything above back to Claude."
