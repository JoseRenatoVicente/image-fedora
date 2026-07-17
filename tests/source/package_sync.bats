#!/usr/bin/env bats
# Source-level tests: consistência das listas de pacotes (fonte única).
# Garante que as listas de instalação e de verificação não se contradizem —
# o drift que esta refatoração de fonte única visa eliminar.

setup() {
    load '../helpers/common'
    # shellcheck source=/dev/null
    source "${REPO_ROOT}/build_files/scripts/shared/package-lists.sh"
    build_packages="${REPO_ROOT}/build_files/scripts/build-packages.sh"
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
    [ "${#COSMIC_REQUIRED[@]}"     -gt 0 ]
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

@test "pacotes instalados não puxam bloat indesejado conhecido" {
    for pkg in kdeplasma-addons kio-gdrive spectacle; do
        if in_list "$pkg" "${INSTALL_PACKAGES[@]}"; then
            echo "'$pkg' puxa pacotes marcados como UNWANTED"
            return 1
        fi
    done
    assert_contains "${REPO_ROOT}/build_files/scripts/build-packages.sh" '--setopt=install_weak_deps=False'
}

@test "nenhum pacote requerido está na lista de remoção" {
    for pkg in "${REQUIRED_PACKAGES[@]}" "${COSMIC_REQUIRED[@]}"; do
        if in_list "$pkg" "${REMOVE_PACKAGES[@]}"; then
            echo "Contradição: '$pkg' é REQUIRED mas está em REMOVE_PACKAGES"
            return 1
        fi
    done
}

@test "nenhum pacote requerido está excluído da instalação" {
    for pkg in "${REQUIRED_PACKAGES[@]}" "${COSMIC_REQUIRED[@]}"; do
        if in_list "$pkg" "${INSTALL_EXCLUDES[@]}"; then
            echo "Contradição: '$pkg' é REQUIRED mas está em INSTALL_EXCLUDES"
            return 1
        fi
    done
}

@test "build deps não constam nas verificações de presença (são removidas)" {
    for pkg in "${BUILD_DEPS[@]}"; do
        if in_list "$pkg" "${REQUIRED_PACKAGES[@]}" "${COSMIC_REQUIRED[@]}"; then
            echo "Contradição: build dep '$pkg' é verificada como REQUIRED mas é removida no build"
            return 1
        fi
    done
}

@test "required hardened_malloc COPR install fails fast" {
    if in_list hardened_malloc "${REQUIRED_PACKAGES[@]}"; then
        assert_not_contains "$build_packages" 'WARN: hardened_malloc não instalado'
    fi
}

@test "remoção de build deps não faz autoremove de runtime em uso" {
    assert_not_contains "${REPO_ROOT}/build_files/scripts/configure/70-build-deps.sh" '--setopt=clean_requirements_on_remove=True'
    assert_contains "${REPO_ROOT}/build_files/scripts/configure/70-build-deps.sh" '--setopt=clean_requirements_on_remove=False'
}

@test "limpeza de órfãos não remove dependências de media em uso (flite/lpcnetfreedv)" {
    run grep -Eq '^[[:space:]]*qt6-qtspeech([[:space:]]|$)' "${REPO_ROOT}/build_files/scripts/build-packages.sh"
    [ "$status" -ne 0 ]
    run grep -Eq '^[[:space:]]*qt6-qtspeech-flite([[:space:]]|$)' "${REPO_ROOT}/build_files/scripts/build-packages.sh"
    [ "$status" -ne 0 ]
}
