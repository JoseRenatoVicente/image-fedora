#!/usr/bin/bash
# Roda dentro da VM de teste. Aguarda a sessão gráfica COSMIC (autologin do
# testuser) arrancar e assentar, depois varre o journal COMPLETO (sistema +
# sessão de utilizador) à procura de ERROS e AVISOS, aplicando uma allowlist
# de ruído conhecido (hardware/VM/upstream cosmético).
# Escreve resultados para /dev/ttyS0 (capturado pelo QEMU -serial mon:stdio).
#
# Níveis de report:
#   PASS  — verificação ok
#   INFO  — informativo (ignorados, progresso)
#   WARN  — aviso surfacado para revisão; NÃO falha o teste
#   FAIL  — erro real; falha o teste (just test-boot → exit 1)
set -uo pipefail

SERIAL="/dev/ttyS0"
TESTUSER="testuser"
FAILED=0

# Janela de scan do journal por prioridade.
#   err  (≤3) → FAIL  (erros reais bloqueiam)
#   warn (=4) → WARN  (surfacados para correção, não bloqueiam)
#
# Allowlist: ruído investigado e confirmado NÃO-acionável a partir da config da
# imagem (hardware/VM ausente). Agrupada por categoria. Tudo o que não estiver
# aqui deve aparecer para podermos corrigir.
#
# NOTA: esta allowlist foi herdada da era KDE/Plasma e ainda não foi revalidada
# contra um boot COSMIC real — as entradas de hardware/VM abaixo devem
# continuar a aplicar-se (são independentes de DE), mas ruído cosmético
# específico do cosmic-comp/cosmic-session ainda não foi levantado/adicionado.
ALLOWLIST=(
    # ── Hardware / kernel / firmware (VM e HW real) ──
    'pci 0000' 'ACPI.*(BIOS|Error)' 'kvm: ' 'nmi_send' 'RAS:' 'tsc:' 'clocksource'
    # ── virtio / QEMU headless / render de software (NÃO ocorre em HW real) ──
    'virtio' 'Failed to open drm node' "couldn't find dev node for drm"
    'main thread was hanging' 'IPv4: martian source' 'll header:' 'pktsetup'
    'BUS_MODULES, HWMON_MODULES' 'no kernel backlight'
    'Charge thresholds are not supported' 'DPMS state changes unimplemented'
    'bpf cannot be resolved'
    # ── Bluetooth / Thunderbolt sem adaptador (VM; em HW real o serviço arranca) ──
    'Bluetooth: hci' 'BlueZ system service is not available' 'org.bluez'
    'compatible running Bluez' 'bluetooth adapter' 'Bolt manager'
    # ── systemd-tmpfiles / SELinux / namespacing benignos ──
    'systemd-tmpfiles.*(already exists|Failed to open path|Failed to parse ACL)'
    'SELinux.*checkreqprot' 'systemd-analyze'
    'Failed to set up mount namespacing.*/proc'
    # ── Resolução de grupos/users no boot precoce (initramfs/pré-sysusers): os
    #    grupos estáticos (audio/video/input/render/kvm/tty/tss…) ainda não existem
    #    quando o tmpfiles/udev corre; o sistema real resolve-os depois. Benigno.
    #    Surge por causa da regeneração do initramfs (necessária p/ virtio_gpu).
    'Failed to resolve (user|group)'
    # ── NetworkManager transitório ──
    "sd-event.*assertion '<dropped>' failed"
    # ── chrony a corrigir o relógio no arranque (RTC da VM dessincronizado) ──
    'System clock (wrong by|was stepped)'
    # ── Verificação de updates fazendo skopeo ao ref bootc. Na imagem de teste
    #    o ref é localhost/fedora-kde-test → sem registry → falha. Em produção é
    #    ghcr.io e funciona. Artefacto exclusivo do teste. ──
    'skopeo' 'check for updates' 'pinging container registry'
)
ALLOWLIST_REGEX=$(IFS='|'; printf '%s' "${ALLOWLIST[*]}")

stamp() { date '+%H:%M:%S'; }
report() {
    local level="$1"; shift
    printf 'BOOT-%s [%s]: %s\n' "$level" "$(stamp)" "$*" | tee -a "$SERIAL" 2>/dev/null || true
    [[ "$level" == "FAIL" ]] && FAILED=1
    return 0
}

printf 'BOOT-INFO [INIT]: boot-health-check arrancou\n' > "$SERIAL" 2>/dev/null || true
printf 'BOOT-INFO [INIT]: boot-health-check arrancou\n'
report INFO "Health check iniciado (após graphical.target)"

# ── 1. Aguarda a sessão gráfica (cosmic-comp do testuser) ────────────────────
# Sem GPU real, o cosmic-comp pode precisar de render de software
# (LIBGL_ALWAYS_SOFTWARE/GALLIUM_DRIVER definidos pelo Containerfile.test).
# Damos até 120s para cosmic-greeter→autologin→cosmic-session.
report INFO "Aguardando sessão gráfica cosmic-comp (testuser)..."
GFX_UP=0
for _ in $(seq 1 60); do
    if pgrep -u "$TESTUSER" cosmic-comp >/dev/null 2>&1; then
        GFX_UP=1; break
    fi
    sleep 2
done
if [[ $GFX_UP -eq 1 ]]; then
    report PASS "Sessão gráfica cosmic-comp arrancou"
    # Deixa a sessão assentar e registar portal/applets/cosmic-panel no journal.
    sleep 30
else
    report FAIL "Sessão gráfica não arrancou (cosmic-comp ausente após 120s)"
fi

# ── 2. Unidades systemd falhadas (sistema) ───────────────────────────────────
# Unidades falhadas levam um bullet "●" na coluna 1 — remove-se antes de extrair o nome.
mapfile -t FAILED_UNITS < <(systemctl list-units --state=failed --no-legend 2>/dev/null | sed 's/^[[:space:]]*●[[:space:]]*//' | awk '{print $1}')
for unit in "${FAILED_UNITS[@]}"; do
    report FAIL "Unidade de sistema falhada: $unit"
done
[[ ${#FAILED_UNITS[@]} -eq 0 ]] && report PASS "Sem unidades de sistema falhadas"

# ── 3. Unidades de utilizador falhadas (sessão do testuser) ──────────────────
TESTUID="$(id -u "$TESTUSER" 2>/dev/null || echo '')"
if [[ -n "$TESTUID" ]]; then
    mapfile -t FAILED_USER_UNITS < <(
        systemctl --user --machine="${TESTUSER}@.host" list-units --state=failed --no-legend 2>/dev/null | sed 's/^[[:space:]]*●[[:space:]]*//' | awk '{print $1}'
    )
    for unit in "${FAILED_USER_UNITS[@]}"; do
        report FAIL "Unidade de utilizador falhada: $unit"
    done
    [[ ${#FAILED_USER_UNITS[@]} -eq 0 ]] && report PASS "Sem unidades de utilizador falhadas"
fi

# ── 4. Erros críticos no journal (prioridade err, ≤3) → FAIL ─────────────────
mapfile -t JERR < <(
    journalctl -p err -b --no-pager -q 2>/dev/null | grep -vE "$ALLOWLIST_REGEX" | head -40
)
if [[ ${#JERR[@]} -eq 0 ]]; then
    report PASS "Sem erros críticos (err) no journal"
else
    for line in "${JERR[@]}"; do
        report FAIL "Journal err: $line"
    done
fi

# ── 5. Avisos no journal (prioridade warning, =4) → WARN (não-fatal) ──────────
mapfile -t JWARN < <(
    journalctl -p warning..warning -b --no-pager -q 2>/dev/null | grep -vE "$ALLOWLIST_REGEX" | head -60
)
if [[ ${#JWARN[@]} -eq 0 ]]; then
    report PASS "Sem avisos (warning) no journal"
else
    report INFO "${#JWARN[@]} aviso(s) surfacado(s) para revisão:"
    for line in "${JWARN[@]}"; do
        report WARN "Journal warn: $line"
    done
fi

# ── 6. Serviços essenciais ativos ────────────────────────────────────────────
# display-manager.service é o alias estável → cosmic-greeter.service
for svc in systemd-oomd tuned firewalld chronyd display-manager; do
    if systemctl is-active "$svc" &>/dev/null; then
        report PASS "Ativo: $svc"
    else
        report FAIL "Inativo: $svc"
    fi
done

# Marcador final (o `just test-boot` espera por esta linha)
if [[ $FAILED -eq 0 ]]; then
    printf 'BOOT-DONE:OK\n' | tee -a "$SERIAL" 2>/dev/null || true
else
    printf 'BOOT-DONE:FAILED\n' | tee -a "$SERIAL" 2>/dev/null || true
fi
# Garante flush do serial antes do poweroff --force
sleep 2
