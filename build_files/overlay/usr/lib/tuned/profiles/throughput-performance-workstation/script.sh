#!/bin/bash
. /usr/lib/tuned/functions

start() {
    [ "$(/usr/bin/systemctl is-enabled scx_loader.service 2>/dev/null)" = "enabled" ] && \
        /usr/bin/scxctl switch -m gaming 2>/dev/null || true
    return 0
}

stop() {
    true
}

process $@
