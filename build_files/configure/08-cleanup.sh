# 08-cleanup.sh — Remove build deps, regenerate initramfs, cleanup, validate repos,
# image info, crypto policy, and tests.
# Sourced by build-configure.sh (not executed directly).

# ─── Remove build deps ────────────────────────────────────────────────────────
echo "::group:: Remove build deps"
BUILD_DEPS=(
    # Toolchain Rust usada para derivar o tema COSMIC (cosmic-theme-gen)
    cargo rust gcc cpp
    # rsync: usado por install-assets.sh para copiar árvores de assets
    rsync
)
FOUND_BUILD_DEPS=()
for pkg in "${BUILD_DEPS[@]}"; do
    rpm -q "$pkg" &>/dev/null && FOUND_BUILD_DEPS+=("$pkg")
done
[[ ${#FOUND_BUILD_DEPS[@]} -gt 0 ]] && dnf5 remove -y --setopt=clean_requirements_on_remove=True "${FOUND_BUILD_DEPS[@]}"
echo "::endgroup::"

# ─── Regenerate initramfs (virtio_gpu para Plymouth em VM) ────────────────────
echo "::group:: Initramfs"
install -Dm644 /ctx/configs/dracut-drm-drivers.conf /etc/dracut.conf.d/02-drm-drivers.conf
KVER=$(ls /usr/lib/modules | sort -V | tail -1)
INITRAMFS="/usr/lib/modules/$KVER/initramfs.img"

depmod "$KVER" 2>/dev/null || true
dracut --force --no-hostonly --force-drivers " virtio_gpu " --kver "$KVER" "$INITRAMFS"
[[ -s "$INITRAMFS" ]] || { echo "FATAL: initramfs vazio após dracut: $INITRAMFS"; exit 1; }

INITRD_MODS=$(lsinitrd --mod "$INITRAMFS" 2>/dev/null)
printf '%s\n' "$INITRD_MODS" | grep -qE '^[[:space:]]*(50)?ostree[[:space:]]*$' \
    || { echo "FATAL: módulo ostree ausente no initramfs regenerado!"; exit 1; }
echo "✓ ostree presente no initramfs"
if lsinitrd "$INITRAMFS" 2>/dev/null | grep -qiE 'virtio.gpu\.ko'; then
    echo "✓ virtio_gpu presente no initramfs"
else
    echo "WARN: virtio_gpu não entrou no initramfs — Plymouth pode não aparecer em VM (HW real ok)"
fi
echo "::endgroup::"

# ─── Cleanup final ────────────────────────────────────────────────────────────
echo "::group:: Cleanup"
# machine-id não deve ser baked na imagem OCI — cada instância gera o seu no
# primeiro boot via systemd-machine-id-setup. Um ID baked causa todas as
# instâncias derivadas da imagem a partilhar o mesmo ID (dbus, journald, etc.).
truncate -s 0 /etc/machine-id
dnf5 clean all
rm -rf /var/cache/dnf /var/log/dnf* /var/log/hawkey*
rm -rf /run/* /tmp/* 2>/dev/null || true
rm -rf /var/lib/dnf/repos /var/lib/dnf/*.lock 2>/dev/null || true
rm -rf /var/lib/flatpak 2>/dev/null || true
rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/info/*
LOCALE_REMOVED=0
while IFS= read -r -d '' dir; do
    rm -rf "$dir" && ((++LOCALE_REMOVED))
done < <(find /usr/share/locale -mindepth 1 -maxdepth 1 \
    ! -name 'pt_BR' ! -name 'en_US' ! -name 'locale.alias' \
    -print0)
echo "Locales removidos: $LOCALE_REMOVED (mantidos: pt_BR, en_US)"
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "::endgroup::"

# ─── Validate repos ───────────────────────────────────────────────────────────
/ctx/shared/validate-repos.sh

# ─── Image info + os-release ─────────────────────────────────────────────────
/ctx/shared/image-info.sh

# ─── Crypto policy (LAST: RSA-2048 rejeitado por FUTURE, bloqueia downloads) ─
echo "::group:: Crypto policy"
update-crypto-policies --set DEFAULT:CHRONY-NTS
echo "::endgroup::"

# ─── Tests (após crypto policy para validar FUTURE) ──────────────────────────
/ctx/shared/tests.sh
