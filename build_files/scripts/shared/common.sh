# shellcheck shell=bash
# Common helpers for build/configuration scripts. Sourced only; no side effects
# beyond function definitions.

install_error_trap() {
    trap 'printf "\033[1;31mERRO linha %s: %s\033[0m\n" "$LINENO" "$BASH_COMMAND" >&2' ERR
}

installed_packages_from() {
    local pkg
    for pkg in "$@"; do
        rpm -q "$pkg" &>/dev/null && printf '%s\n' "$pkg"
    done
}
