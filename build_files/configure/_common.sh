# Common setup for all configure modules.
# Sourced by build-configure.sh — not executed directly.

set -euo pipefail
trap 'printf "\033[1;31mERRO linha %s: %s\033[0m\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

export IMAGE_NAME="${IMAGE_NAME:-fedora}"
export IMAGE_PRETTY_NAME="${IMAGE_PRETTY_NAME:-Fedora}"
export IMAGE_VENDOR="${IMAGE_VENDOR:-}"
export SHA_HEAD_SHORT="${SHA_HEAD_SHORT:-}"
# SOURCE_DATE_EPOCH só deve ser exportado quando tem um valor numérico válido
if [[ "${SOURCE_DATE_EPOCH:-}" =~ ^[0-9]+$ ]]; then
    export SOURCE_DATE_EPOCH
else
    unset SOURCE_DATE_EPOCH
fi

# shellcheck source=shared/copr-helpers.sh
source /ctx/shared/copr-helpers.sh
