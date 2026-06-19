#!/usr/bin/env bash
#
# BetterLockScreen Dial — SAFE PREVIEW (no sudo, no real lock, no system changes).
#
# Builds a throwaway copy of the system Plasma shell under a DIFFERENT package id
# (so it cannot affect your real desktop or real lock screen), layers in the dial
# QML, and opens it in KDE's --testing greeter (an ordinary window). Close it and
# everything is cleaned up automatically.
#
# Usage:  ./preview.sh
#
# SPDX-License-Identifier: MIT

set -euo pipefail

PREVIEW_ID="com.betterlockscreen.dialpreview"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
OURLS="$SCRIPT_DIR/lockscreen"
SYS=/usr/share/plasma/shells/org.kde.plasma.desktop
DST="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/shells/$PREVIEW_ID"
GREET=/usr/libexec/kscreenlocker_greet

[ -d "$SYS" ]   || { echo "Stock Plasma shell not found at $SYS" >&2; exit 1; }
[ -x "$GREET" ] || { echo "kscreenlocker_greet not found at $GREET" >&2; exit 1; }
[ -f "$OURLS/DialIndicator.qml" ] || { echo "Dial QML not found in $OURLS" >&2; exit 1; }

GPID=""
cleanup() { [ -n "$GPID" ] && kill -- -"$GPID" 2>/dev/null || true; pkill -P "${GPID:-0}" 2>/dev/null || true; rm -rf "$DST"; }
trap cleanup EXIT INT TERM

# 1) throwaway full copy of the system shell under a NEW id (real desktop untouched)
rm -rf "$DST"; mkdir -p "$(dirname "$DST")"
cp -r "$SYS" "$DST"

# 2) layer in our dial lockscreen (only the 3 changed/added files)
cp "$OURLS/MainBlock.qml" "$OURLS/LockScreenUi.qml" "$OURLS/DialIndicator.qml" "$DST/contents/lockscreen/"

# 3) rename the package id so it is distinct from org.kde.plasma.desktop
python3 - "$DST/metadata.json" "$PREVIEW_ID" <<'PY'
import json, sys
path, pid = sys.argv[1], sys.argv[2]
m = json.load(open(path))
m.setdefault("KPlugin", {})
m["KPlugin"]["Id"] = pid
m["KPlugin"]["Name"] = "BetterLockScreen Dial (preview)"
json.dump(m, open(path, "w"), indent=2)
PY

echo "Opening the dial in a preview window (this is NOT a real lock)…"
echo "  • Type some characters — the ring should flash as you press keys."
echo "  • Try a wrong password (ring -> dark red), it will clear."
echo "  • Look for Sleep / Restart / Shut Down buttons (no Hibernate)."
echo
setsid "$GREET" --testing --shell "$PREVIEW_ID" &
GPID=$!
echo "Preview running (pid $GPID). If you don't see it, check your taskbar."
read -rp $'\nPress Enter here to close the preview and clean up… '
