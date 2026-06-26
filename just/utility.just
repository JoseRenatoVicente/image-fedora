# Check Just Syntax
[group('Just')]
check:
    #!/usr/bin/bash
    for file in Justfile just/*.just; do
        echo "Checking syntax: $file"
        just --unstable --fmt --check -f "$file"
    done

# Fix Just Syntax
[group('Just')]
fix:
    #!/usr/bin/bash
    for file in Justfile just/*.just; do
        echo "Formatting syntax: $file"
        just --unstable --fmt -f "$file"
    done

# Clean Repo
[group('Utility')]
clean:
    #!/usr/bin/bash
    set -eoux pipefail
    rm -rf _build-bib.* _build-test.* _build_podman_scp.*
    rm -f previous.manifest.json
    rm -f changelog.md
    rm -f output.env
    rm -rf output/

# Sudo Clean Repo
[group('Utility')]
[private]
sudo-clean:
    just sudoif just clean

# sudoif bash function
[group('Utility')]
[private]
sudoif command *args:
    #!/usr/bin/bash
    function sudoif(){
        if [[ "${UID}" -eq 0 ]]; then
            "$@"
        elif [[ "$(command -v sudo)" && -n "${SUDO_ASKPASS:-}" ]] && [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
            /usr/bin/sudo --askpass "$@" || exit 1
        elif [[ "$(command -v sudo)" ]]; then
            /usr/bin/sudo "$@" || exit 1
        else
            exit 1
        fi
    }
    sudoif {{ command }} {{ args }}

# Runs shell check on all Bash scripts
lint:
    #!/usr/bin/env bash
    set -eoux pipefail
    # Check if shellcheck is installed
    if ! command -v shellcheck &> /dev/null; then
        echo "shellcheck could not be found. Please install it."
        exit 1
    fi
    # Run shellcheck por extensão E por shebang de shell — apanha scripts sem
    # extensão (ex.: usr/libexec/*, usr/bin/dnf) que de outra forma escapariam.
    {
        find build_files tests tools -type f \( -name "*.sh" -o -name "*.bats" -o -name "*.bash" \)
        find build_files tests tools -type f -exec sh -c 'head -1 "$1" | grep -qE "^#!.*\b(ba)?sh\b"' _ {} \; -print
    } | sort -u | xargs shellcheck -e SC1091 -e SC2154

# Runs shfmt on all Bash scripts
format:
    #!/usr/bin/env bash
    set -eoux pipefail
    # Check if shfmt is installed
    if ! command -v shfmt &> /dev/null; then
        echo "shfmt could not be found. Please install it."
        exit 1
    fi
    {
        find build_files tests tools -type f \( -name "*.sh" -o -name "*.bats" -o -name "*.bash" \)
        find build_files tests tools -type f -exec sh -c 'head -1 "$1" | grep -qE "^#!.*\b(ba)?sh\b"' _ {} \; -print
    } | sort -u | xargs shfmt --write
