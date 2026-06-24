#!/usr/bin/bash
# NÃO CHAMAR ESTE SCRIPT DURANTE O BUILD NORMAL.
#
# O dracut em contexto de container não tem acesso a /proc, /sys, /dev reais.
# Isso produz um initramfs sem módulos de storage (virtio_blk, virtio_scsi,
# nvme) e a VM não consegue montar o root → initrd-switch-root falha.
#
# As configurações em /etc/dracut.conf.d/ (omit-firewire, omit-thunderbolt)
# já ficam na imagem e aplicam-se automaticamente quando o bootc actualiza
# o kernel no sistema do utilizador (dracut corre com acesso real ao hardware).
#
# Só usar este script em contextos onde /proc, /sys e /dev estão montados
# correctamente (ex: dentro do sistema já instalado via "bootc update").

echo "::group:: ===$(basename "$0")==="
set -euox pipefail

KERNEL_VERSION=$(rpm -q --queryformat="%{evr}.%{arch}" kernel-core)

export DRACUT_NO_XATTR=1
dracut --hostonly --kver "${KERNEL_VERSION}" --reproducible -v -f \
    "/usr/lib/modules/${KERNEL_VERSION}/initramfs.img"
chmod 0600 "/usr/lib/modules/${KERNEL_VERSION}/initramfs.img"

echo "::endgroup::"
