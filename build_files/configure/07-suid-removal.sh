# 07-suid-removal.sh — Strip SUID/SGID bits and remove unnecessary setuid binaries.
# Sourced by build-configure.sh (not executed directly).

# ─── SUID removal ─────────────────────────────────────────────────────────────
echo "::group:: SUID removal"
# Strip SUID/SGID de todos os binários em /usr excepto sudo (KDE/kdesu precisa)
find /usr -type f -perm /6000 -print0 | while IFS= read -r -d '' binary; do
    case "$binary" in
        /usr/bin/sudo|/usr/bin/su) continue ;;
        *) chmod ug-s "$binary" && echo "Stripped: $binary" ;;
    esac
done
# Remover binários desnecessários com histórico de vulnerabilidades SUID
rm -f /usr/bin/chsh /usr/bin/chfn /usr/bin/pkexec
# Substituir SUID por capabilities mínimas onde necessário
setcap cap_sys_admin=ep /usr/bin/fusermount3 2>/dev/null \
    || echo "WARN: setcap fusermount3 falhou"
setcap cap_dac_read_search,cap_audit_write=ep /usr/sbin/unix_chkpwd 2>/dev/null \
    || echo "WARN: setcap unix_chkpwd falhou"
echo "::endgroup::"
