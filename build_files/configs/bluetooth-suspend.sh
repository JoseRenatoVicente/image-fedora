#!/bin/sh
# Save/restore Bluetooth rfkill state across suspend/resume.
# Prevents the common "Bluetooth disconnected after suspend" regression.
case "${1}" in
    pre)
        if rfkill list bluetooth 2>/dev/null | grep -q "Soft blocked: no"; then
            touch /run/bluetooth-was-enabled
        fi
        ;;
    post)
        if [ -f /run/bluetooth-was-enabled ]; then
            rm -f /run/bluetooth-was-enabled
            rfkill unblock bluetooth
        fi
        ;;
esac
