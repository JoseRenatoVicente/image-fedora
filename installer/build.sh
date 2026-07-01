#!/usr/bin/bash
# Ref: https://github.com/ublue-os/bazzite/blob/main/installer/build.sh

set -exo pipefail
{ export PS4='+( ${BASH_SOURCE}:${LINENO} ): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'; } 2>/dev/null

INSTALL_IMAGE_PAYLOAD=${INSTALL_IMAGE_PAYLOAD:?}

# /root pode ser symlink em base-atomic
mkdir -p "$(realpath /root)"

# Ficheiros estáticos do instalador (perfil Anaconda, overrides, etc.).
cp -a /src/system_files/shared/. /

# ── Initramfs live ────────────────────────────────────────────────────────────
dnf install -y dracut-live
kernel=$(find /usr/lib/modules -maxdepth 1 -type d -printf '%P\n' \
    | grep -E '^[0-9]' | sort -V | tail -1)
DRACUT_NO_XATTR=1 dracut -v --force --zstd --reproducible --no-hostonly \
    --add "dmsquash-live dmsquash-live-autooverlay" \
    "/usr/lib/modules/${kernel}/initramfs.img" "${kernel}"

# ── Live session (livesys-scripts) ───────────────────────────────────────────
dnf install -y livesys-scripts

# Detecta o desktop environment pelo ficheiro .desktop da sessão
_session=$(find /usr/share/wayland-sessions/ /usr/share/xsessions/ \
    -maxdepth 1 -type f -name '*.desktop' -printf '%P' -quit 2>/dev/null || true)
case $_session in
    cosmic*)  _livesys_session=cosmic ;;
    plasma*)  _livesys_session=kde ;;
    gnome*)   _livesys_session=gnome ;;
    *)        _livesys_session=gnome ;;
esac
sed -i "s/^livesys_session=.*/livesys_session=${_livesys_session}/" \
    /etc/sysconfig/livesys
systemctl enable livesys.service livesys-late.service

# Handler COSMIC para o livesys — configura autologin via greetd
if [[ "${_livesys_session}" == "cosmic" ]] && \
   [[ ! -f /usr/libexec/livesys/sessions.d/livesys-cosmic ]]; then
    install -Dm755 /src/sessions.d/livesys-cosmic \
        /usr/libexec/livesys/sessions.d/livesys-cosmic
fi

# ── Anaconda ──────────────────────────────────────────────────────────────────
dnf install -y --allowerasing anaconda-live libblockdev-{btrfs,lvm,dm}
mkdir -p /var/lib/rpm-state

# ── Payload offline para o Anaconda ───────────────────────────────────────────
if mountpoint -q /usr/lib/containers/storage; then
    podman save --format oci-archive "$INSTALL_IMAGE_PAYLOAD" \
        | podman load --storage-opt additionalimagestore=''
else
    podman pull "$INSTALL_IMAGE_PAYLOAD"
fi

# Referência da imagem para o kickstart (strip scheme, keep registry path).
# Preserve registries with ports and digest references; splitting on ':' breaks
# refs such as registry:5000/org/image:tag.
_ref="${INSTALL_IMAGE_PAYLOAD##*://}"
install_image_ref="${_ref}"

# ── Script de instalação --user (gerado com a lista embebida) ─────────────────
# Extrai os app IDs do ficheiro de flatpaks (linha "app/ID/arch/branch" → "ID")
mapfile -t _app_ids < <(sed -n 's|^app/\([^/]*\)/.*|\1|p' /src/flatpaks)

cat > /etc/flatpak-user-setup.sh << SCRIPT_EOF
#!/bin/bash
set -euo pipefail
STAMP="\${XDG_CONFIG_HOME:-\$HOME/.config}/flatpak-user-setup.done"
[[ -f "\$STAMP" ]] && exit 0
flatpak remote-add --user --if-not-exists flathub \\
    https://dl.flathub.org/repo/flathub.flatpakrepo
APPS=(
$(printf '    %s\n' "${_app_ids[@]}")
)
for pkg in "\${APPS[@]}"; do
    flatpak install --user -y flathub "\$pkg" || true
done
mkdir -p "\$(dirname "\$STAMP")"
touch "\$STAMP"
SCRIPT_EOF
chmod 755 /etc/flatpak-user-setup.sh

# Kickstart defaults — Anaconda lê este ficheiro no arranque
cat >> /usr/share/anaconda/interactive-defaults.ks << EOF

# Instala a partir do container storage local da live ISO (offline)
ostreecontainer --url=${install_image_ref} --transport=containers-storage --no-signature-verification

# Copia o script de setup de flatpaks para o sistema instalado
%post --nochroot --erroronfail --log=/tmp/flatpak-setup.log
install -Dm755 /etc/flatpak-user-setup.sh /mnt/sysroot/etc/flatpak-user-setup.sh
%end

# Cria serviço systemd user no skel — corre no primeiro login de cada utilizador
%post --erroronfail --log=/tmp/flatpak-user-service.log
mkdir -p /etc/skel/.config/systemd/user/default.target.wants
cat > /etc/skel/.config/systemd/user/flatpak-user-setup.service << 'SERVICE_EOF'
[Unit]
Description=Flatpak User Setup
Wants=network-online.target
After=network-online.target
ConditionUser=!@system
ConditionPathIsDirectory=%h
ConditionPathExists=!%E/flatpak-user-setup.done

[Service]
Type=oneshot
ExecStart=/etc/flatpak-user-setup.sh
Restart=on-failure
RestartSec=30s
RestartMaxDelaySec=1800s
RestartSteps=10
SERVICE_EOF
ln -sf ../flatpak-user-setup.service \
    /etc/skel/.config/systemd/user/default.target.wants/flatpak-user-setup.service

# Aponta para o registry para receber actualizações futuras
bootc switch --mutate-in-place --enforce-container-sigpolicy --transport registry ${install_image_ref}
%end

EOF

# ── /var/tmp maior para o ostree durante a instalação ────────────────────────
rm -rf /var/tmp && mkdir /var/tmp
install -Dm644 /src/var-tmp.mount /etc/systemd/system/var-tmp.mount
systemctl enable var-tmp.mount

# ── EFI para o bootc-image-builder ────────────────────────────────────────────
dnf install -y grub2-efi-x64-cdboot
mkdir -p /boot/efi
cp -av /usr/lib/efi/*/*/EFI /boot/efi/
cp -v /boot/efi/EFI/fedora/grubx64.efi /boot/efi/EFI/BOOT/fbx64.efi

# Timezone UTC por defeito na live session
rm -f /etc/localtime
systemd-firstboot --timezone UTC

# Configuração GRUB do ISO para o bootc-image-builder
mkdir -p /usr/lib/bootc-image-builder
cp /src/iso.yaml /usr/lib/bootc-image-builder/iso.yaml

dnf clean all
