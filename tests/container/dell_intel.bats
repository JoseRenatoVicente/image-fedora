#!/usr/bin/env bats
# Container tests — run inside the built image
# Tests: Dell/Intel specific — fingerprint, sensors, firmware, tuned

setup() {
    load '../helpers/common'
}

# ── Fingerprint PAM ─────────────────────────────────────────────────────────

@test "fingerprint PAM is configured" {
    if command -v authselect >/dev/null 2>&1; then
        authselect current 2>/dev/null | grep -qi 'fingerprint\|fprint' \
            || grep -Rqs 'pam_fprintd\.so' /etc/pam.d
    else
        grep -Rqs 'pam_fprintd\.so' /etc/pam.d
    fi
}

# ── Intel SOF audio ─────────────────────────────────────────────────────────

@test "Intel SOF firmware is present" {
    [[ -d /lib/firmware/intel/sof || -d /usr/lib/firmware/intel/sof ]]
}

# ── libfprint ────────────────────────────────────────────────────────────────

@test "libfprint udev rules exist" {
    [[ -e /usr/lib/udev/rules.d/70-libfprint-2.rules || -e /usr/lib/udev/rules.d/60-libfprint-2.rules ]]
}

# ── tuned profile ────────────────────────────────────────────────────────────

@test "tuned active profile is balanced" {
    grep -q 'balanced' /etc/tuned/active_profile
}
