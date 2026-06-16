# Run a virtual machine with the specified image type and configuration
_run-vm $target_image $tag $type $config:
    #!/usr/bin/bash
    set -eoux pipefail

    # Determine the image file based on the type
    image_file="output/${type}/disk.${type}"
    if [[ $type == iso ]]; then
        image_file="output/bootiso/install.iso"
    fi

    # Build the image if it does not exist
    if [[ ! -f "${image_file}" ]]; then
        just "build-${type}" "$target_image" "$tag"
    fi

    # Determine an available port to use
    port=8006
    while grep -q :${port} <<< $(ss -tunalp); do
        port=$(( port + 1 ))
    done
    echo "Using Port: ${port}"
    echo "Connect to http://localhost:${port}"

    # Set up the arguments for running the VM
    run_args=()
    run_args+=(--rm --privileged)
    run_args+=(--pull=newer)
    run_args+=(--publish "127.0.0.1:${port}:8006")
    run_args+=(--env "CPU_CORES=4")
    run_args+=(--env "RAM_SIZE=6G")
    run_args+=(--env "DISK_SIZE=64G")
    run_args+=(--env "BOOT_MODE=uefi")
    run_args+=(--env "TPM=Y")
    run_args+=(--env "WIDTH=1920")
    run_args+=(--env "HEIGHT=1080")
    run_args+=(--device=/dev/kvm)

    # Passa dispositivos DRI do host para habilitar aceleração GPU (VirtGL)
    # Sem estes devices o qemux não consegue criar /dev/dri/card0 e cai em CPU rendering
    if [[ -d /dev/dri ]]; then
        run_args+=(--device=/dev/dri)
        run_args+=(--env "GPU=Y")
    else
        run_args+=(--env "GPU=N")
        echo "WARN: /dev/dri não encontrado, GPU desabilitada"
    fi

    run_args+=(--volume "${PWD}/${image_file}":"/boot.${type}")
    run_args+=(docker.io/qemux/qemu)

    # Run the VM and open the browser to connect (como usuário real se via sudo)
    if [[ -n "${SUDO_USER:-}" ]]; then
      (sleep 30 && sudo -u "${SUDO_USER}" xdg-open http://localhost:"$port") &
    else
      (sleep 30 && xdg-open http://localhost:"$port") &
    fi
    podman run "${run_args[@]}"

# Run a virtual machine from a QCOW2 image
[group('Run Virtal Machine')]
run-vm-qcow2 $target_image=("localhost/" + image_name) $tag=default_tag: && (_run-vm target_image tag "qcow2" "disk_config/disk.toml")

# Run a virtual machine from a RAW image
[group('Run Virtal Machine')]
run-vm-raw $target_image=("localhost/" + image_name) $tag=default_tag: && (_run-vm target_image tag "raw" "disk_config/disk.toml")

# Run a virtual machine from an ISO
[group('Run Virtal Machine')]
run-vm-iso $target_image=("localhost/" + image_name) $tag=default_tag: && (_run-vm target_image tag "iso" "disk_config/iso.toml")

# Run a virtual machine with native QEMU + virtio-vga-gl (OpenGL real via virgl)
# Requer: qemu-system-x86_64, edk2-ovmf  →  sudo dnf install -y qemu-kvm edk2-ovmf
# Usa virtio-vga-gl: dá GL acelerado (virgl) → sem o flood de "ZINK: failed to
# choose pdev" que o qxl provoca (qxl não tem Vulkan). Contrapartida: o virtio_gpu
# NÃO está no initramfs, então o Plymouth não aparece nesta VM (cai em texto). No
# HW real o Plymouth funciona (rhgb + driver nativo no initramfs). Para ter Plymouth
# TAMBÉM na VM seria preciso pôr virtio_gpu/simpledrm no initramfs (regenerá-lo).
[group('Run Virtal Machine')]
run-vm-gl type="qcow2" ram="8G" cpus="4":
    #!/usr/bin/env bash
    set -euo pipefail

    image_file="output/{{ type }}/disk.{{ type }}"
    if [[ ! -f "${image_file}" ]]; then
        echo "Imagem não encontrada: ${image_file}"
        echo "Execute primeiro: just build-{{ type }}"
        exit 1
    fi

    # Verificar dependências
    if ! command -v qemu-system-x86_64 &>/dev/null; then
        echo "qemu-system-x86_64 não encontrado. Instale com:"
        echo "  sudo dnf install -y qemu-kvm edk2-ovmf"
        exit 1
    fi

    # Localizar firmware UEFI
    OVMF_CODE=""
    OVMF_VARS_SRC=""
    for candidate in \
        /usr/share/edk2/ovmf/OVMF_CODE.fd \
        /usr/share/OVMF/OVMF_CODE.fd \
        /usr/share/qemu/OVMF_CODE.fd; do
        if [[ -f "$candidate" ]]; then
            OVMF_CODE="$candidate"
            OVMF_VARS_SRC="${candidate/CODE/VARS}"
            break
        fi
    done
    if [[ -z "$OVMF_CODE" ]]; then
        echo "OVMF não encontrado. Instale: sudo dnf install -y edk2-ovmf"
        exit 1
    fi

    # VARS precisa de uma cópia gravável por sessão
    # Usa XDG_RUNTIME_DIR (/run/user/UID) que tem espaço garantido; /tmp pode ter quota
    _tmpdir="${XDG_RUNTIME_DIR:-${HOME}/.cache}"
    OVMF_VARS_TMP=$(mktemp "${_tmpdir}/OVMF_VARS_XXXXXXXXXX.fd")
    cp "${OVMF_VARS_SRC:-${OVMF_CODE/CODE/VARS}}" "$OVMF_VARS_TMP"
    trap "rm -f '$OVMF_VARS_TMP'" EXIT

    RAM_BYTES=$(echo "{{ ram }}" | numfmt --from=iec)
    RAM_MB=$(( RAM_BYTES / 1024 / 1024 ))

    echo "Iniciando VM COSMIC — janela SDL com OpenGL (virtio-vga-gl/virgl)"
    echo "  Imagem : ${image_file}"
    echo "  RAM    : ${RAM_MB}M  CPUs: {{ cpus }}"
    echo "  GPU    : virtio-vga-gl (OpenGL via host; sem Plymouth na VM)"

    qemu-system-x86_64 \
        -enable-kvm \
        -machine q35 \
        -cpu host \
        -smp "{{ cpus }}" \
        -m "${RAM_MB}M" \
        -device virtio-vga-gl,xres=1920,yres=1080 \
        -display sdl,gl=on \
        -drive "if=pflash,format=raw,readonly=on,file=${OVMF_CODE}" \
        -drive "if=pflash,format=raw,file=${OVMF_VARS_TMP}" \
        -drive "file=${image_file},format={{ type }},if=virtio,cache=writeback,discard=unmap" \
        -netdev user,id=net0 \
        -device virtio-net-pci,netdev=net0 \
        -device virtio-balloon-pci \
        -device virtio-rng-pci \
        -usb -device usb-tablet \
        -audiodev pa,id=snd0 \
        -device ich9-intel-hda \
        -device hda-duplex,audiodev=snd0 \
        -rtc base=localtime \
        -boot menu=on

# Run a virtual machine using systemd-vmspawn
[group('Run Virtal Machine')]
spawn-vm rebuild="0" type="qcow2" ram="6G":
    #!/usr/bin/env bash

    set -euo pipefail

    [ "{{ rebuild }}" -eq 1 ] && echo "Rebuilding the ISO" && just build-vm {{ rebuild }} {{ type }}

    systemd-vmspawn \
      -M "bootc-image" \
      --console=gui \
      --cpus=2 \
      --ram=$(echo {{ ram }}| /usr/bin/numfmt --from=iec) \
      --network-user-mode \
      --vsock=false --pass-ssh-key=false \
      -i ./output/**/*.{{ type }}
