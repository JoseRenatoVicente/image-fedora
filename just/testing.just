# ── Testes automatizados ──────────────────────────────────────────────────────

# Corre os testes source-level sem construir a imagem.
[group('Testing')]
validate-source:
    bats tests/source/

# Corre os testes estáticos contra a imagem de container já construída (sem boot).
# Rápido (~30s). Equivalente ao que corre no final do build, mas invocável a qualquer momento.
# Requer: just build (ou just rebuild-qcow2 — a imagem container deve existir)
[group('Testing')]
test-container $target_image=image_name $tag=default_tag:
    #!/usr/bin/env bash
    set -euo pipefail
    local_ref="${target_image}:${tag}"
    podman image exists "${local_ref}" 2>/dev/null || local_ref="localhost/${target_image}:${tag}"
    if ! podman image exists "${local_ref}" 2>/dev/null; then
        echo "Imagem não encontrada. Execute primeiro: just build"
        exit 1
    fi
    echo "A correr testes estáticos em: ${local_ref}"
    podman run --rm \
        --security-opt label=disable \
        -v "$(pwd)/tests:/tests:ro,z" \
        "${local_ref}" \
        bash -c 'dnf5 install -y --setopt=install_weak_deps=False bats 2>/dev/null; bats /tests/container/'

# Constrói a imagem de teste (extensão da produção com health check de boot).
# A imagem de produção deve existir localmente; `just test-boot` reconstrói-a antes.
[group('Testing')]
test-build:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! podman image exists "localhost/{{ image_name }}:{{ default_tag }}" 2>/dev/null && \
       ! podman image exists "{{ image_name }}:{{ default_tag }}" 2>/dev/null; then
        echo "Imagem de produção não encontrada. Execute primeiro: just build"
        exit 1
    fi
    echo "A construir imagem de teste..."
    podman build \
        -f Containerfile.test \
        --tag "fedora-kde-test:latest" \
        .
    echo "Imagem de teste pronta: fedora-kde-test:latest"

# Boot test headless: reconstrói a imagem de produção, constrói QCOW2 de teste,
# arranca em QEMU sem display, aguarda o health check e reporta PASS/FAIL.
# Dependências: qemu-kvm edk2-ovmf  →  sudo dnf install -y qemu-kvm edk2-ovmf
[group('Testing')]
test-boot timeout="420":
    #!/usr/bin/env bash
    set -euo pipefail

    # Garante que o teste usa a imagem de produção gerada a partir do working tree atual.
    just build

    # Garante que a imagem de teste está construída sobre a produção atual.
    just test-build

    if ! command -v qemu-system-x86_64 &>/dev/null; then
        echo "qemu-system-x86_64 não encontrado. Instale: sudo dnf install -y qemu-kvm edk2-ovmf"
        exit 1
    fi

    # Localizar OVMF
    OVMF_CODE=""
    for candidate in \
        /usr/share/edk2/ovmf/OVMF_CODE.fd \
        /usr/share/OVMF/OVMF_CODE.fd \
        /usr/share/qemu/OVMF_CODE.fd; do
        [[ -f "$candidate" ]] && OVMF_CODE="$candidate" && break
    done
    [[ -z "$OVMF_CODE" ]] && { echo "OVMF não encontrado. Instale: sudo dnf install -y edk2-ovmf"; exit 1; }

    _tmpdir="${XDG_RUNTIME_DIR:-${HOME}/.cache}"
    OVMF_VARS=$(mktemp "${_tmpdir}/OVMF_VARS_XXXXXX.fd")
    cp "${OVMF_CODE/CODE/VARS}" "$OVMF_VARS"
    trap "rm -f '$OVMF_VARS'" EXIT

    # Construir QCOW2 de teste via bootc-image-builder
    echo "A converter imagem de teste para QCOW2..."
    just _rootful_load_image localhost/fedora-kde-test latest
    TEST_BUILDTMP=$(mktemp -d -p "${PWD}" _build-test.XXXXXX)
    sudo podman run --rm --privileged --pull=newer \
        --net=host \
        --security-opt label=type:unconfined_t \
        -v "$(pwd)/disk_config/disk.toml":/config.toml:ro \
        -v "${TEST_BUILDTMP}":/output \
        -v /var/lib/containers/storage:/var/lib/containers/storage \
        "${bib_image}" \
        --type qcow2 --use-librepo=True --rootfs=btrfs \
        localhost/fedora-kde-test:latest
    sudo chown -R "$USER:$USER" "${TEST_BUILDTMP}" 2>/dev/null || true

    TEST_QCOW="${TEST_BUILDTMP}/qcow2/disk.qcow2"
    [[ -f "$TEST_QCOW" ]] || { echo "QCOW2 de teste não encontrado em $TEST_QCOW"; exit 1; }

    RESULTS_LOG=$(mktemp "${_tmpdir}/boot-test-results.XXXXXX")
    CLEAN_TEST_BUILDTMP=1
    trap 'rm -f "'$OVMF_VARS'"; [[ "${CLEAN_TEST_BUILDTMP:-0}" == "1" ]] && rm -rf "'${TEST_BUILDTMP}'"' EXIT

    echo ""
    echo "A iniciar boot test headless (timeout: {{ timeout }}s)..."
    echo "QCOW2 : $TEST_QCOW"
    echo "Log   : $RESULTS_LOG"
    echo ""

    # Boot headless:
    #   -display none       → descarta output VGA (sem janela)
    #   -device virtio-vga  → VGA existe (cosmic-greeter/cosmic-comp precisa de um device)
    #   -serial mon:stdio   → serial (ttyS0) capturado em stdout → log
    # NÃO usar -nographic aqui: implica sem VGA device e redirects serial
    # de forma diferente — conflita com -display none + -serial explícito.
    qemu-system-x86_64 \
        -enable-kvm \
        -machine q35,kernel-irqchip=split \
        -device intel-iommu,intremap=on,caching-mode=on \
        -cpu host \
        -smp 4 \
        -m 4G \
        -display none \
        -device virtio-vga \
        -serial mon:stdio \
        -no-reboot \
        -drive "if=pflash,format=raw,readonly=on,file=${OVMF_CODE}" \
        -drive "if=pflash,format=raw,file=${OVMF_VARS}" \
        -drive "file=${TEST_QCOW},format=qcow2,if=virtio,cache=writeback" \
        -netdev user,id=net0 \
        -device virtio-net-pci,netdev=net0 \
        -device virtio-rng-pci \
        -device virtio-balloon-pci \
        >"$RESULTS_LOG" 2>&1 &
    QEMU_PID=$!

    echo "QEMU PID: $QEMU_PID — aguardando marcadores BOOT- (timeout: {{ timeout }}s)..."
    echo "─────────────────────────────────────────────────"

    # Mostra linhas BOOT- em tempo real enquanto espera
    tail -n 0 -f "$RESULTS_LOG" 2>/dev/null | grep --line-buffered "BOOT-" &
    TAIL_PID=$!

    # Poll por BOOT-DONE ou até timeout
    DEADLINE=$(( SECONDS + {{ timeout }} ))
    while [[ $SECONDS -lt $DEADLINE ]] && kill -0 "$QEMU_PID" 2>/dev/null; do
        grep -q "BOOT-DONE:" "$RESULTS_LOG" 2>/dev/null && break
        sleep 5
    done

    kill "$TAIL_PID" 2>/dev/null || true
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true

    echo ""
    echo "═══════════════════════════════════════"

    # Analisar resultados
    FAILS=$(grep "^BOOT-FAIL" "$RESULTS_LOG" 2>/dev/null || true)
    WARNS=$(grep "^BOOT-WARN" "$RESULTS_LOG" 2>/dev/null || true)
    DONE=$(grep "^BOOT-DONE:" "$RESULTS_LOG" 2>/dev/null || true)

    # Avisos são informativos (não falham o teste) mas são sempre exibidos.
    if [[ -n "$WARNS" ]]; then
        echo ""
        echo "── AVISOS surfacados (não-fatais, para correção) ──"
        echo "$WARNS"
    fi

    if [[ -z "$DONE" ]]; then
        CLEAN_TEST_BUILDTMP=0
        echo "RESULTADO: INCONCLUSIVO (timeout sem BOOT-DONE)"
        echo ""
        echo "Possíveis erros no log:"
        grep -iE "fail|error|emergency|dracut|ostree|mount|root" "$RESULTS_LOG" 2>/dev/null | tail -80 || true
        echo ""
        echo "Últimas linhas do log:"
        tail -80 "$RESULTS_LOG"
        echo ""
        echo "Log preservado para análise: $RESULTS_LOG"
        echo "QCOW2 preservado para análise: $TEST_QCOW"
        exit 1
    elif [[ -n "$FAILS" ]]; then
        CLEAN_TEST_BUILDTMP=0
        echo "RESULTADO: FALHOU"
        echo ""
        echo "$FAILS"
        echo ""
        echo "Log preservado para análise: $RESULTS_LOG"
        echo "QCOW2 preservado para análise: $TEST_QCOW"
        exit 1
    else
        echo "RESULTADO: PASSOU ✓"
        grep "^BOOT-PASS\|^BOOT-INFO" "$RESULTS_LOG" 2>/dev/null || true
    fi
    echo "═══════════════════════════════════════"
