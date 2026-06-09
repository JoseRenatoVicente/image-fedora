#!/usr/bin/env bash
# Disables GPU-intensive KWin effects in virtual machine environments.
# Runs at every login via autostart; re-enables effects if moved to real hardware.
set -euo pipefail

KWINRC="$HOME/.config/kwinrc"

if systemd-detect-virt -q 2>/dev/null; then
    kwriteconfig6 --file "$KWINRC" --group Plugins --key blurEnabled "false"
    kwriteconfig6 --file "$KWINRC" --group Plugins --key roundcornersEnabled "false"
    kwriteconfig6 --file "$KWINRC" --group Plugins --key kwin4_effect_roundcornersEnabled "false"
else
    kwriteconfig6 --file "$KWINRC" --group Plugins --key blurEnabled "true"
    kwriteconfig6 --file "$KWINRC" --group Plugins --key roundcornersEnabled "true"
    kwriteconfig6 --file "$KWINRC" --group Plugins --key kwin4_effect_roundcornersEnabled "true"
fi

qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
