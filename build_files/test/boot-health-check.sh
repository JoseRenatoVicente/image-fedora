#!/usr/bin/bash
# Roda dentro da VM de teste após multi-user.target estabilizar.
# Escreve resultados para /dev/ttyS0 (capturado pelo QEMU -serial mon:stdio).
# Nota: não testa sessão gráfica — KWin/Wayland não inicializa sem GPU real.
# Esses checks são feitos pelos testes estáticos (just test-container).
set -uo pipefail

SERIAL="/dev/ttyS0"
FAILED=0

# Escreve imediatamente para confirmar que o serviço arrancou
printf 'BOOT-INFO [INIT]: boot-health-check arrancou\n' > "$SERIAL" 2>/dev/null || true
printf 'BOOT-INFO [INIT]: boot-health-check arrancou\n'

stamp() { date '+%H:%M:%S'; }
report() {
    local level="$1"; shift
    printf 'BOOT-%s [%s]: %s\n' "$level" "$(stamp)" "$*" | tee -a "$SERIAL" 2>/dev/null || true
    [[ "$level" == "FAIL" ]] && FAILED=1
}

report INFO "Health check iniciado (multi-user.target)"

# 1. Unidades systemd falhadas (exclui serviços esperados-headless)
mapfile -t FAILED_UNITS < <(systemctl list-units --state=failed --no-legend 2>/dev/null | awk '{print $1}')
HEADLESS_EXPECTED=(sddm.service display-manager.service plymouth-quit-wait.service)
for unit in "${FAILED_UNITS[@]}"; do
    skip=0
    for expected in "${HEADLESS_EXPECTED[@]}"; do
        [[ "$unit" == "$expected" ]] && skip=1 && break
    done
    [[ $skip -eq 1 ]] && report INFO "Ignorado headless: $unit" && continue
    report FAIL "Unidade falhada: $unit"
done
[[ ${#FAILED_UNITS[@]} -eq 0 ]] && report PASS "Sem unidades systemd falhadas"

# 2. Erros críticos no journal (exclui ruído de hardware e comportamento esperado bootc)
JOURNAL_ERRORS=$(journalctl -p err -b --no-pager -q 2>/dev/null |
    grep -vE "pci 0000|Bluetooth|ACPI.*BIOS|kvm:|nmi_send|RAS|tsc|clocksource|drm|virtio" |
    grep -vE "systemd-tmpfiles.*(already exists|Failed to open path)" |
    grep -vE "SELinux.*checkreqprot" |
    grep -vE "systemd-analyze" |
    head -30)
if [[ -z "$JOURNAL_ERRORS" ]]; then
    report PASS "Sem erros críticos no journal"
else
    while IFS= read -r line; do
        report FAIL "Journal: $line"
    done <<< "$JOURNAL_ERRORS"
fi

# 3. Serviços essenciais ativos (sem SDDM: não arranca headless sem GPU)
for svc in earlyoom tuned firewalld chronyd; do
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
