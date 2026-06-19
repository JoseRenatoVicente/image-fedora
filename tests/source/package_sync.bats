#!/usr/bin/env bats
# Source-level tests: consistência das listas de pacotes (fonte única).
# Garante que as listas de instalação e de verificação não se contradizem —
# o drift que esta refatoração de fonte única visa eliminar.

setup() {
    load '../helpers/common'
    # shellcheck source=/dev/null
    source "${REPO_ROOT}/build_files/scripts/shared/package-lists.sh"
    in_list() {  # in_list <needle> <haystack...>
        local needle="$1"; shift
        local x
        for x in "$@"; do [ "$x" = "$needle" ] && return 0; done
        return 1
    }
}

@test "package-lists.sh define todas as arrays esperadas" {
    [ "${#INSTALL_PACKAGES[@]}" -gt 0 ]
    [ "${#INSTALL_EXCLUDES[@]}" -gt 0 ]
    [ "${#REMOVE_PACKAGES[@]}"  -gt 0 ]
    [ "${#BUILD_DEPS[@]}"       -gt 0 ]
    [ "${#REQUIRED_PACKAGES[@]}" -gt 0 ]
    [ "${#KDE_REQUIRED[@]}"     -gt 0 ]
    [ "${#UNWANTED_PACKAGES[@]}" -gt 0 ]
}

@test "nenhum pacote indesejado está também na lista de instalação" {
    for pkg in "${UNWANTED_PACKAGES[@]}"; do
        if in_list "$pkg" "${INSTALL_PACKAGES[@]}" "${BUILD_DEPS[@]}"; then
            echo "Contradição: '$pkg' é UNWANTED mas está em INSTALL_PACKAGES/BUILD_DEPS"
            return 1
        fi
    done
}

@test "nenhum pacote requerido está na lista de remoção" {
    for pkg in "${REQUIRED_PACKAGES[@]}" "${KDE_REQUIRED[@]}"; do
        if in_list "$pkg" "${REMOVE_PACKAGES[@]}"; then
            echo "Contradição: '$pkg' é REQUIRED mas está em REMOVE_PACKAGES"
            return 1
        fi
    done
}

@test "nenhum pacote requerido está excluído da instalação" {
    for pkg in "${REQUIRED_PACKAGES[@]}" "${KDE_REQUIRED[@]}"; do
        if in_list "$pkg" "${INSTALL_EXCLUDES[@]}"; then
            echo "Contradição: '$pkg' é REQUIRED mas está em INSTALL_EXCLUDES"
            return 1
        fi
    done
}

@test "build deps não constam nas verificações de presença (são removidas)" {
    for pkg in "${BUILD_DEPS[@]}"; do
        if in_list "$pkg" "${REQUIRED_PACKAGES[@]}" "${KDE_REQUIRED[@]}"; then
            echo "Contradição: build dep '$pkg' é verificada como REQUIRED mas é removida no build"
            return 1
        fi
    done
}
