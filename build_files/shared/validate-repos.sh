#!/usr/bin/bash
echo "::group:: ===$(basename "$0")==="
set -eou pipefail

REPOS_DIR="/etc/yum.repos.d"
VALIDATION_FAILED=0
ENABLED_REPOS=()

check_repo_file() {
    local repo_file="$1"
    [[ ! -f "$repo_file" ]] && return 0
    if grep -q "^enabled=1" "$repo_file" 2>/dev/null; then
        echo "HABILITADO (problema): $(basename "$repo_file")"
        ENABLED_REPOS+=("$(basename "$repo_file")")
        VALIDATION_FAILED=1
        echo "   Secções habilitadas:"
        local section=""
        while IFS= read -r line; do
            [[ "$line" =~ ^\[.*\]$ ]] && section="$line"
            [[ "$line" =~ ^enabled=1 ]] && echo "     - $section"
        done < "$repo_file"
    else
        echo "OK (desabilitado): $(basename "$repo_file")"
    fi
}

echo "--- COPRs ---"
for repo in "$REPOS_DIR"/_copr:copr.fedorainfracloud.org:*.repo; do
    [[ -f "$repo" ]] && check_repo_file "$repo"
done

echo "--- RPM Fusion ---"
for repo in "$REPOS_DIR"/rpmfusion-*.repo; do
    [[ -f "$repo" ]] && check_repo_file "$repo"
done

echo "--- Terceiros ---"
for name in vscode.repo tailscale.repo docker-ce.repo; do
    [[ -f "$REPOS_DIR/$name" ]] && check_repo_file "$REPOS_DIR/$name"
done

if [[ $VALIDATION_FAILED -eq 1 ]]; then
    echo ""
    echo "VALIDAÇÃO FALHOU — os seguintes repos estão ainda HABILITADOS:"
    for r in "${ENABLED_REPOS[@]}"; do echo "  • $r"; done
    echo "::endgroup::"
    exit 1
fi

echo "Todos os repos de terceiros estão desabilitados."
echo "::endgroup::"
