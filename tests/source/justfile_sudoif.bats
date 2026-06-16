#!/usr/bin/env bats
# Source-level tests: Justfile askpass policy

setup() {
    load '../helpers/common'
}

@test "Justfile askpass uses SUDO_ASKPASS not SSH_ASKPASS" {
    run grep 'ASKPASS' "${REPO_ROOT}/just/utility.just"
    [ "$status" -eq 0 ]
    [[ "$output" == *'SUDO_ASKPASS'* ]]
}
