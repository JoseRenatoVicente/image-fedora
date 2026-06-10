#!/usr/bin/env bash
set -euo pipefail

repo_root=$(dirname "$(dirname "$0")")
justfile="${repo_root}/Justfile"

askpass_line=$(grep -n 'ASKPASS' "${justfile}" || true)

if [[ -z "${askpass_line}" ]]; then
    echo "failed: could not find askpass-related line in Justfile"
    exit 1
fi

if [[ "${askpass_line}" != *'SUDO_ASKPASS'* ]]; then
    echo "failed: askpass branch must require SUDO_ASKPASS, not SSH_ASKPASS"
    echo "line: ${askpass_line}"
    exit 1
fi

echo "ok: askpass branch requires SUDO_ASKPASS"
