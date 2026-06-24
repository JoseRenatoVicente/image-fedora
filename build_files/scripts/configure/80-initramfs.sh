#!/bin/bash
# Regenera um initramfs GENÉRICO (não host-only) para baquear os módulos extra das
# nossas dracut.conf.d (crypt/tpm2-tss/fido2 + virtio_gpu) e valida que os drivers
# essenciais de boot (ostree + storage) ficam presentes — sem eles não arranca.
#
# NÃO usar --hostonly: o dracut num container de build não tem acesso a /proc,
# /sys nem /dev reais, por isso só "vê" o storage do container (overlayfs). Em
# modo host-only o initramfs sai SEM os drivers de storage do alvo real
# (virtio_blk, nvme, ahci, virtio_scsi) → na VM/máquina real o root nunca monta
# → rd.emergency=halt → "boot has failed ... Halting". --no-hostonly inclui todos
# os drivers genéricos, que é o que uma imagem bootc precisa.
set -euo pipefail
trap 'printf "\033[1;31mERRO linha %s: %s\033[0m\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

# /root é symlink → /var/roothome no layout bootc/ostree. Em container de build o
# alvo não existe, o que faz o dracut falhar em "installing '/root'". Criar o dir
# antes do dracut resolve o erro; no sistema real é gerido por systemd-tmpfiles.
mkdir -p /var/roothome

KVER=$(find /usr/lib/modules -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | sort -V | tail -1)
INITRAMFS="/usr/lib/modules/$KVER/initramfs.img"

depmod "$KVER" 2>/dev/null || true
dracut --force --no-hostonly --kver "$KVER" "$INITRAMFS"
[[ -s "$INITRAMFS" ]] || { echo "FATAL: initramfs vazio após dracut: $INITRAMFS"; exit 1; }

INITRD_MODS=$(lsinitrd --mod "$INITRAMFS" 2>/dev/null)
printf '%s\n' "$INITRD_MODS" | grep -qE '^[[:space:]]*(50)?ostree[[:space:]]*$' \
    || { echo "FATAL: módulo ostree ausente no initramfs regenerado!"; exit 1; }
echo "✓ ostree presente no initramfs"

# Sanity dos drivers de storage: sem pelo menos um, o root não monta no alvo real.
# Falha cedo no build em vez de produzir uma imagem que dá "boot has failed".
INITRD_DRIVERS=$(lsinitrd "$INITRAMFS" 2>/dev/null)
printf '%s\n' "$INITRD_DRIVERS" | grep -qE '(virtio_blk|virtio_scsi|nvme|ahci|sd_mod)\.ko' \
    || { echo "FATAL: nenhum driver de storage no initramfs — boot falharia (não usar --hostonly no container)!"; exit 1; }
echo "✓ drivers de storage presentes no initramfs"
