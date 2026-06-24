#!/bin/bash
# Regenera um initramfs host-only para o hardware alvo e valida que o modulo ostree
# continua presente — sem ele a imagem nao arranca.
set -euo pipefail
trap 'printf "\033[1;31mERRO linha %s: %s\033[0m\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

# /root é symlink → /var/roothome no layout bootc/ostree. Em container de build o
# alvo não existe, o que faz o dracut falhar em "installing '/root'". Criar o dir
# antes do dracut resolve o erro; no sistema real é gerido por systemd-tmpfiles.
mkdir -p /var/roothome

KVER=$(find /usr/lib/modules -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | sort -V | tail -1)
INITRAMFS="/usr/lib/modules/$KVER/initramfs.img"

depmod "$KVER" 2>/dev/null || true
dracut --force --hostonly --kver "$KVER" "$INITRAMFS"
[[ -s "$INITRAMFS" ]] || { echo "FATAL: initramfs vazio após dracut: $INITRAMFS"; exit 1; }

INITRD_MODS=$(lsinitrd --mod "$INITRAMFS" 2>/dev/null)
printf '%s\n' "$INITRD_MODS" | grep -qE '^[[:space:]]*(50)?ostree[[:space:]]*$' \
    || { echo "FATAL: módulo ostree ausente no initramfs regenerado!"; exit 1; }
echo "✓ ostree presente no initramfs"
