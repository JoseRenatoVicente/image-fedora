#!/usr/bin/env bash
set -euo pipefail

repo_root=$(dirname "$(dirname "$0")")
failed=0

fail() {
    echo "FAIL: $*" >&2
    failed=1
}

assert_contains() {
    local file=$1
    local pattern=$2

    if ! grep -Fq -- "$pattern" "$file"; then
        fail "expected '$pattern' in $file"
    fi
}

assert_not_contains() {
    local file=$1
    local pattern=$2

    if grep -Fq -- "$pattern" "$file"; then
        fail "unexpected '$pattern' in $file"
    fi
}

configure="${repo_root}/build_files/build-configure.sh"
packages="${repo_root}/build_files/build-packages.sh"
runtime_tests="${repo_root}/build_files/shared/tests.sh"
shell_setup="${repo_root}/build_files/configs/fedora-shell-setup"
dev_setup="${repo_root}/build_files/configs/fedora-dev-setup"
cosmic_layout="${repo_root}/build_files/configs/fedora-cosmic-layout-setup"
justfile="${repo_root}/Justfile"

assert_contains "$configure" 'fedora-cosmic-layout-setup'
assert_contains "$configure" '/usr/lib/systemd/user/fedora-cosmic-layout-setup.service'
assert_contains "$configure" '/etc/systemd/user/timers.target.wants/fedora-cosmic-layout-setup.timer'
assert_contains "$runtime_tests" 'fedora-cosmic-layout-setup'
assert_contains "$cosmic_layout" 'layout_version='
assert_contains "$cosmic_layout" 'fedora-cosmic-layout.version'

assert_contains "$shell_setup" 'MARKER="# >>> fedora-shell-setup >>>"'
assert_contains "$shell_setup" 'starship init zsh'
assert_contains "$shell_setup" 'zoxide init zsh'
assert_contains "$shell_setup" 'direnv hook zsh'
assert_contains "$shell_setup" 'sudo-command-line()'
assert_contains "$shell_setup" 'fj()'
assert_contains "$shell_setup" 'fgb()'
assert_contains "$shell_setup" 'zsh-autosuggestions'
assert_contains "$shell_setup" 'zsh-syntax-highlighting'
assert_not_contains "$shell_setup" 'oh-my-zsh'
assert_not_contains "$shell_setup" 'powerlevel10k'

assert_contains "$dev_setup" 'distrobox create'
assert_contains "$dev_setup" 'toolbox create'
assert_contains "$dev_setup" '.local/share/fedora-dev-setup'
assert_contains "$dev_setup" 'opencode-ai@${OPENCODE_NPM_VERSION}'

for heavy_pkg in terraform kubectl helm k9s nodejs_ golang rust cargo java-latest-openjdk; do
    if grep -Eq "^[[:space:]]*${heavy_pkg}([[:space:]]|$)" "$packages"; then
        fail "heavy dev package should not be installed in base: ${heavy_pkg}"
    fi
done

assert_contains "$justfile" 'validate-source:'
assert_contains "$justfile" './tests/cosmic_shell_dev_policy_test.sh'

if [[ $failed -ne 0 ]]; then
    exit 1
fi

echo "ok: COSMIC shell/dev policy checks passed"
