#!/bin/bash
# Hardening em runtime de build: instala as políticas SELinux CIL (socket denial
# + user namespace) e remove/neutraliza binários SUID perigosos, substituindo-os
# por capabilities mínimas onde necessário.
set -euo pipefail
trap 'printf "\033[1;31mERRO linha %s: %s\033[0m\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

# ─── SELinux CIL policies ────────────────────────────────────────────────────
CIL_FILES=(
    /ctx/assets/selinux/secureblue_socket_utils.cil
    /ctx/assets/selinux/secureblue_deny_ipsec_sockets.cil
    /ctx/assets/selinux/secureblue_deny_obscure_sockets.cil
    /ctx/assets/selinux/secureblue_deny_alg_sockets.cil
    /ctx/assets/selinux/secureblue_deny_packet_radio_sockets.cil
    /ctx/assets/selinux/container-ptrace.cil
    # REMOVIDOS: harden_userns.cil + harden_container_userns.cil.
    # O `deny ... (user_namespace (create))` quebrava dois fluxos centrais:
    #   • bwrap (unconfined_t) → sandbox interno dos navegadores flatpak
    #     (Firefox, Tor Browser), que criam user namespaces aninhados;
    #   • podman (container_runtime_t) → rootless podman/distrobox.
    # No Fedora esses processos rodam sob domínios não-privilegiados
    # (unconfined_t / container_runtime_t) e não há domínio SELinux por-app,
    # então não dá para liberar só o navegador/container sem afrouxar tudo.
    # Como esta imagem usa Firefox/Tor flatpak + distrobox, mantemos o userns
    # não-privilegiado (padrão do Fedora). Electron (Discord/Teams/Obsidian)
    # não é afetado — usa zypak, sem userns aninhado.
    /ctx/assets/selinux/grant_userns.cil
    /ctx/assets/selinux/userns_deny_unconfined_relabels.cil
)
# Instalados com prioridade 300 (>200 dos pacotes RPM, <400 do admin local)
semodule -v -X 300 -i "${CIL_FILES[@]}"
# SELinux booleans: nega ptrace via MAC (camada adicional ao Yama ptrace_scope=2)
# container_allow_ptrace é definido no container-ptrace.cil acima
setsebool -P deny_ptrace=on container_allow_ptrace=off || \
    echo "WARN: setsebool falhou (SELinux não activo no build container; booleans aplicados no arranque)"
# Fedora 44 atribui install_exec_t a /usr/bin/bootc por erro de política.
# Esse tipo bloqueia execução via run0 (unconfined_t não aceita install_exec_t
# como entrypoint). Corrigimos para bin_t antes do restorecon abaixo.
semanage fcontext -m -t bin_t '/usr/bin/bootc' 2>/dev/null || \
    echo "WARN: semanage fcontext para bootc falhou (política ausente no container de build)"
restorecon -FRv /usr 2>/dev/null || true

# ─── SUID removal ────────────────────────────────────────────────────────────
# Strip SUID/SGID de todos os binários em /usr excepto:
#   sudo/su               — kdesu + escalada normal
#   pkexec                — anaconda-live/liveinst eleva via polkit
#   polkit-agent-helper-1 — autentica via PAM para polkit (sem SUID, TODA a
#                           autenticação administrativa falha no KDE)
#   passwd                — necessita SUID para escrever /etc/shadow
find /usr -type f -perm /6000 -print0 | while IFS= read -r -d '' binary; do
    case "$binary" in
        /usr/bin/sudo|\
        /usr/bin/su|\
        /usr/bin/pkexec|\
        /usr/lib/polkit-1/polkit-agent-helper-1|\
        /usr/bin/passwd) continue ;;
        *) chmod ug-s "$binary" && echo "Stripped: $binary" ;;
    esac
done
# Remover binários desnecessários com histórico de vulnerabilidades SUID.
# pkexec é preservado: anaconda-live/liveinst depende dele para elevar via polkit.
rm -f /usr/bin/chsh /usr/bin/chfn
# ─── Root account hardening ──────────────────────────────────────────────────
# Bloqueia a password root (já sem password no build bootc, mas torna explícito)
# e muda o shell para nologin — impede login directo mesmo com emergency console PAM.
# Não fazemos chage -E0 (expiry absoluta) para não interferir com scripts de sistema.
passwd -l root
usermod -s /usr/sbin/nologin root

# Substituir SUID por capabilities mínimas onde necessário
setcap cap_sys_admin=ep /usr/bin/fusermount3 2>/dev/null \
    || echo "WARN: setcap fusermount3 falhou"
setcap cap_dac_read_search,cap_audit_write=ep /usr/sbin/unix_chkpwd 2>/dev/null \
    || echo "WARN: setcap unix_chkpwd falhou"
