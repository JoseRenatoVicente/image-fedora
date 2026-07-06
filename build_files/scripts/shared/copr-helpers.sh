#!/usr/bin/bash
set -euo pipefail

# Instala pacotes de um COPR em isolamento:
# 1. habilita o COPR
# 2. desabilita-o imediatamente
# 3. instala via --enablerepo (ativa só para este install)
# Isto impede que o COPR substitua pacotes Fedora via prioridade normal de repo.
copr_install_isolated() {
    local copr_name="$1"
    shift
    local packages=("$@")

    if [[ ${#packages[@]} -eq 0 ]]; then
        echo "ERROR: copr_install_isolated: nenhum pacote especificado para $copr_name" >&2
        return 1
    fi

    local repo_id="copr:copr.fedorainfracloud.org:${copr_name//\//:}"
    echo "Instalando [${packages[*]}] do COPR ${copr_name} (isolado)"
    dnf5 -y copr enable "$copr_name"
    dnf5 -y copr disable "$copr_name"
    dnf5 -y install --enablerepo="$repo_id" "${packages[@]}"
    echo "Instalado: ${packages[*]} de $copr_name"
}
