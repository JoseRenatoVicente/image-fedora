# 06-selinux.sh — SELinux CIL policies (socket denial + user namespace hardening).
# Sourced by build-configure.sh (not executed directly).

# ─── SELinux CIL policies (socket denial + user namespace hardening) ─────────
echo "::group:: SELinux CIL policies"
CIL_FILES=(
    /ctx/selinux/secureblue_socket_utils.cil
    /ctx/selinux/secureblue_deny_ipsec_sockets.cil
    /ctx/selinux/secureblue_deny_obscure_sockets.cil
    /ctx/selinux/secureblue_deny_alg_sockets.cil
    /ctx/selinux/secureblue_deny_packet_radio_sockets.cil
    /ctx/selinux/container-ptrace.cil
    /ctx/selinux/harden_userns.cil
    /ctx/selinux/harden_container_userns.cil
    /ctx/selinux/grant_userns.cil
    /ctx/selinux/userns_deny_unconfined_relabels.cil
)
# Instalados com prioridade 300 (>200 dos pacotes RPM, <400 do admin local)
semodule -v -X 300 -i "${CIL_FILES[@]}"
# SELinux booleans: nega ptrace via MAC (camada adicional ao Yama ptrace_scope=2)
# container_allow_ptrace é definido no container-ptrace.cil acima
setsebool -P deny_ptrace=on container_allow_ptrace=off || \
    echo "WARN: setsebool falhou (SELinux não activo no build container; booleans aplicados no arranque)"
restorecon -FRv /usr 2>/dev/null || true
echo "::endgroup::"
