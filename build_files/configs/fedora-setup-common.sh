# shellcheck shell=bash
# Helpers partilhados pelos scripts de primeiro-boot (fedora-*-setup).
# Instalado em /usr/libexec/fedora-setup-common.sh e carregado via `source`.
# Centraliza a verificação de integridade para que TODAS as descargas externas
# (instaladores curl|bash e clones git) sejam pinadas e verificadas de forma
# uniforme — evita que um script esqueça o checksum.

# safe_run <url> <sha256_esperado> [args...]
# Baixa o instalador, confere o SHA256 e só então o executa com os args dados.
safe_run() {
    local url="$1" expected_sha="$2"
    shift 2
    local tmp
    tmp="$(mktemp)"
    trap 'rm -f "$tmp"' RETURN
    curl -fsSL "$url" -o "$tmp"
    local actual_sha
    actual_sha="$(sha256sum "$tmp" | cut -d' ' -f1)"
    if [[ "$actual_sha" != "$expected_sha" ]]; then
        notify-send -a 'Fedora' -i 'dialog-error' -u critical \
            "SHA256 mismatch: $url — instalação cancelada por segurança." 2>/dev/null || true
        echo "FATAL: SHA256 mismatch para $url (esperado $expected_sha, obtido $actual_sha)" >&2
        return 1
    fi
    bash "$tmp" "$@"
}
