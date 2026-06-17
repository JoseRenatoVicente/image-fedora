# tests/helpers/common.bash — Shared BATS helpers for all test suites.

# Repo root (works whether bats runs from repo root or tests/ subdir)
# shellcheck disable=SC2034  # consumido pelos ficheiros de teste que fazem source
REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"

# assert_contains FILE PATTERN — fail if fixed-string PATTERN is not in FILE
assert_contains() {
    local file="$1" pattern="$2"
    if ! grep -Fq -- "$pattern" "$file"; then
        echo "expected '$pattern' in $file" >&2
        return 1
    fi
}

# assert_not_contains FILE PATTERN — fail if fixed-string PATTERN IS in FILE
assert_not_contains() {
    local file="$1" pattern="$2"
    if grep -Fq -- "$pattern" "$file"; then
        echo "unexpected '$pattern' in $file" >&2
        return 1
    fi
}

# assert_file_exists PATH
assert_file_exists() {
    if [[ ! -e "$1" ]]; then
        echo "expected path to exist: $1" >&2
        return 1
    fi
}

# assert_file_not_exists PATH
assert_file_not_exists() {
    if [[ -e "$1" ]]; then
        echo "expected path to NOT exist: $1" >&2
        return 1
    fi
}

# assert_regex_match FILE PATTERN
assert_regex_match() {
    local file="$1" pattern="$2"
    if ! grep -Eq -- "$pattern" "$file"; then
        echo "expected regex '$pattern' to match in $file" >&2
        return 1
    fi
}
