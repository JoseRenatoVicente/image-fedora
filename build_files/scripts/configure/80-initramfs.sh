#!/bin/bash
# Regenera um initramfs HOST-ONLY enxuto, forçando via /etc/dracut.conf.d os
# drivers essenciais de storage/crypt/virtio_gpu, e valida que ostree + storage
# ficam presentes — sem eles não arranca.
#
# Porquê --hostonly agora: em testes, dracut no container de build consegue
# gerar initramfs host-only de ~60 MB (vs ~235 MB genérico) porque os drivers de
# storage críticos são explicitamente adicionados em
# /etc/dracut.conf.d/03-storage-drivers.conf (add_drivers). Os drivers
# virtio_blk/sd_mod/ahci/libahci são built-in no kernel fc44, por isso não
# precisam de .ko no initramfs; nvme e virtio_scsi são adicionados pela config.
# O modo genérico incluía centenas de firmwares/drivers de GPU não essenciais no
# initrd, inflacionando a ISO.
#
# A verificação no fim aceita drivers presentes no initramfs OU built-in no
# kernel (modules.builtin), evitando falsos-negativos.
set -euo pipefail
trap 'printf "\033[1;31mERRO linha %s: %s\033[0m\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

# /root é symlink → /var/roothome no layout bootc/ostree. Em container de build o
# alvo não existe, o que faz o dracut falhar em "installing '/root'". Criar o dir
# antes do dracut resolve o erro; no sistema real é gerido por systemd-tmpfiles.
mkdir -p /var/roothome

KVER=$(find /usr/lib/modules -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | sort -V | tail -1)
INITRAMFS="/usr/lib/modules/$KVER/initramfs.img"

depmod "$KVER" 2>/dev/null || true
dracut --force --hostonly --tmpdir /tmp --kver "$KVER" "$INITRAMFS"
[[ -s "$INITRAMFS" ]] || { echo "FATAL: initramfs vazio após dracut: $INITRAMFS"; exit 1; }

INITRD_MODS=$(lsinitrd --mod "$INITRAMFS" 2>/dev/null)
printf '%s\n' "$INITRD_MODS" | grep -qE '^[[:space:]]*(50)?ostree[[:space:]]*$' \
    || { echo "FATAL: módulo ostree ausente no initramfs regenerado!"; exit 1; }
echo "✓ ostree presente no initramfs"

# Sanity dos drivers de storage: sem pelo menos um, o root não monta no alvo real.
# Falha cedo no build em vez de produzir uma imagem que dá "boot has failed".
#
# Um driver conta como presente se estiver no initramfs (módulo .ko) OU compilado
# no kernel (modules.builtin) — um driver builtin monta o root sem precisar de
# estar no initramfs. Em fc44 virtio_blk/ahci/sd_mod/libahci são BUILTIN, por isso
# uma verificação que só aceita .ko dá falso-negativo (era a causa do "boot has
# failed" no check, não no boot real).
STORAGE_RE='virtio_blk|virtio_scsi|nvme|ahci|sd_mod'
BUILTIN_FILE="/usr/lib/modules/$KVER/modules.builtin"

STORAGE_IN_INITRD=$(lsinitrd "$INITRAMFS" 2>/dev/null \
    | grep -oE "($STORAGE_RE)\.ko" | sort -u || true)
STORAGE_BUILTIN=$(grep -oE "($STORAGE_RE)\.ko" "$BUILTIN_FILE" 2>/dev/null \
    | sort -u || true)

# Diagnóstico (sempre visível no log do build).
echo "── drivers de storage ──"
echo "  módulos no initramfs : ${STORAGE_IN_INITRD//$'\n'/ }"
echo "  builtin no kernel    : ${STORAGE_BUILTIN//$'\n'/ }"
echo "  .ko de storage em disco para $KVER:"
find "/usr/lib/modules/$KVER" -regextype posix-extended \
    -regex ".*($STORAGE_RE)\.ko.*" -printf '    %p\n' 2>/dev/null | sort || true

if [[ -z "$STORAGE_IN_INITRD" && -z "$STORAGE_BUILTIN" ]]; then
    echo "FATAL: nenhum driver de storage (nem módulo no initramfs nem builtin no" \
         "kernel) — boot falharia! Verificar add_drivers em" \
         "/etc/dracut.conf.d/03-storage-drivers.conf e a presença de kernel-modules."
    exit 1
fi
echo "✓ drivers de storage cobertos (módulo no initramfs e/ou builtin no kernel)"
