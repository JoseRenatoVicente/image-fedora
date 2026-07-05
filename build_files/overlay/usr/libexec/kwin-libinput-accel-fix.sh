#!/usr/bin/env bash
# KWin's [Libinput][Defaults][Touchpad|Pointer] fallback in kcminputrc is
# honored for boolean keys (e.g. NaturalScroll) but NOT for PointerAcceleration
# — confirmed live via the org.kde.KWin.InputDevice D-Bus interface on KWin
# 6.7.1: the property stayed at its default (0.0) despite a correct kcminputrc
# entry. Apply the value directly to each pointer device via D-Bus instead.
# Runs at every login via autostart.
set -euo pipefail

ACCEL="0.45"
MANAGER_PATH="/org/kde/KWin/InputDevice"

list_output=$(gdbus call --session --dest org.kde.KWin \
    --object-path "$MANAGER_PATH" \
    --method org.kde.KWin.InputDeviceManager.ListPointers 2>/dev/null) || exit 0

while read -r sysname; do
    [[ -z "$sysname" ]] && continue
    path="$MANAGER_PATH/$sysname"

    supports=$(gdbus call --session --dest org.kde.KWin --object-path "$path" \
        --method org.freedesktop.DBus.Properties.Get \
        org.kde.KWin.InputDevice supportsPointerAcceleration 2>/dev/null) || continue
    [[ "$supports" == *"true"* ]] || continue

    gdbus call --session --dest org.kde.KWin --object-path "$path" \
        --method org.freedesktop.DBus.Properties.Set \
        org.kde.KWin.InputDevice pointerAcceleration "<$ACCEL>" >/dev/null 2>&1 || true
done < <(grep -oP "(?<=')[^']+(?=')" <<< "$list_output")
