#!/usr/bin/bash
# Roda dentro da VM de teste. Aguarda a sessão gráfica Plasma (autologin do
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
# imagem (hardware/VM ausente, ou bug cosmético de upstream KDE). Agrupada por
# categoria. Tudo o que não estiver aqui deve aparecer para podermos corrigir.
ALLOWLIST=(
    # ── Hardware / kernel / firmware (VM e HW real) ──
    'pci 0000' 'ACPI.*(BIOS|Error)' 'kvm: ' 'nmi_send' 'RAS:' 'tsc:' 'clocksource'
    # ── virtio / QEMU headless / render de software (NÃO ocorre em HW real) ──
    'virtio' 'Failed to open drm node' "couldn't find dev node for drm"
    'main thread was hanging' 'IPv4: martian source' 'll header:' 'pktsetup'
    'BUS_MODULES, HWMON_MODULES' 'no kernel backlight'
    'Charge thresholds are not supported' 'DPMS state changes unimplemented'
    'powerdevil.backlighthelper' 'bpf cannot be resolved'
    # ── Bluetooth / Thunderbolt sem adaptador (VM; em HW real o serviço arranca) ──
    'Bluetooth: hci' 'BlueZ system service is not available' 'org.bluez'
    'compatible running Bluez' 'bluetooth adapter' 'Bolt manager'
    # ── systemd-tmpfiles / SELinux / namespacing benignos ──
    'systemd-tmpfiles.*(already exists|Failed to open path)'
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
    # ── Discover: verifica updates fazendo skopeo ao ref bootc. Na imagem de teste
    #    o ref é localhost/fedora-kde-test → sem registry → falha. Em produção é
    #    ghcr.io e funciona. Artefacto exclusivo do teste. ──
    'skopeo' 'check for updates' 'pinging container registry'
    'Didn.t find any Discover backend' 'Unexpected transport format'
    'org/kde/discover' 'Only binding to one of multiple key bindings'
    # ── plasmashell cosmético (a sessão funciona; entradas órfãs/QML upstream) ──
    # NOTA: 'error when loading applet' NÃO está allowlistado de propósito — é o
    # fantasma do painel Mokka que estamos a corrigir (systemtray containment).
    # Se reaparecer, deve surgir como WARN para sabermos.
    'Entry is not valid' 'File name empty' 'QQmlComponent: Component is not ready'
    'Unable to assign'
    # ── Cosmético upstream KDE (não corrigível sem patch dos pacotes KDE) ──
    'is not named after the D-Bus name' 'kded module name .* is invalid'
    'QDBusObjectPath: invalid path' 'Failed to register with host portal'
    'overrides a member of the base object' 'qtvirtualkeyboard'
    'No object for name' 'is not an XDG toplevel'
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

# ── 1. Aguarda a sessão gráfica (KWin Wayland do testuser) ───────────────────
# Sem GPU real, KWin cai em render de software (LIBGL_ALWAYS_SOFTWARE/KWIN_COMPOSE=Q
# definidos pelo Containerfile.test). Damos até 120s para SDDM→autologin→Plasma.
report INFO "Aguardando sessão gráfica KWin Wayland (testuser)..."
GFX_UP=0
for _ in $(seq 1 60); do
    if pgrep -u "$TESTUSER" kwin_wayland >/dev/null 2>&1; then
        GFX_UP=1; break
    fi
    sleep 2
done
if [[ $GFX_UP -eq 1 ]]; then
    report PASS "Sessão gráfica KWin Wayland arrancou"
    # Deixa a sessão assentar e registar portal/kded/plasmashell no journal.
    sleep 30
else
    report FAIL "Sessão gráfica não arrancou (kwin_wayland ausente após 120s)"
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

# ── 3b. Painel Plasma: fantasma de containment (plugin vazio) ────────────────
# Causa do "error when loading applet \"\"". Lê o appletsrc em runtime do testuser
# (escrito pelo plasmashell na 1ª sessão) e reporta plugins vazios.
APPLETSRC_RT="/var/home/${TESTUSER}/.config/plasma-org.kde.plasma.desktop-appletsrc"
if [[ -f "$APPLETSRC_RT" ]]; then
    GHOSTS=$(grep -c '^plugin=$' "$APPLETSRC_RT" 2>/dev/null || echo 0)
    if [[ "$GHOSTS" -gt 0 ]]; then
        report WARN "Painel: $GHOSTS containment(s) com plugin vazio no appletsrc (fantasma)"
        # Mostra as seções afetadas para diagnóstico
        grep -nE '^\[Containments\]|^plugin=$' "$APPLETSRC_RT" 2>/dev/null | grep -B1 '^[0-9]*:plugin=$' | while IFS= read -r l; do report INFO "  appletsrc: $l"; done
    else
        report PASS "Painel: sem fantasmas (nenhum plugin vazio no appletsrc)"
    fi
else
    report INFO "Painel: appletsrc de runtime ainda não escrito ($APPLETSRC_RT)"
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
# display-manager.service é o alias estável → plasmalogin.service (rebrand do SDDM)
for svc in earlyoom tuned firewalld chronyd display-manager; do
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
