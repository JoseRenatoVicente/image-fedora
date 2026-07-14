#!/bin/bash
# build-uki.sh — compõe e assina o Unified Kernel Image (UKI) do deployment,
# via `bootc container ukify` (bootc 1.15+), a correr no stage `uki` do
# Containerfile contra o rootfs já configurado do stage `base` (montado
# read-only em /target).
#
# Porquê um stage à parte: `bootc container ukify --rootfs /` recusa-se a
# operar sobre o filesystem ACTIVO do RUN (precisa de calcular o digest
# composefs de um alvo estático) — por isso corre aqui contra /target
# (bind-mount de outro stage), não inline em build-configure.sh. Os pacotes
# ukify/sbsign também já não estão em `base` a esta altura (70-build-deps.sh
# já os removeu); instalam-se de novo só neste stage descartável.
#
# Duas chaves distintas:
#   • PCR (systemd-measure): sela a Signed PCR Policy do PCR 11 — o LUKS é
#     enrolado contra a CHAVE PÚBLICA (ver /usr/bin/tpm2-luks-enroll), não
#     contra o valor do PCR em si, por isso um UKI novo (kernel/initrd
#     diferentes a cada update) continua a desbloquear sem reenroll desde
#     que assinado com a mesma chave.
#   • MOK (Secure Boot / sbsign): a mesma usada para o systemd-bootx64.efi
#     em 65-secureboot-sign.sh — o firmware só arranca o UKI depois de
#     enrolada em cada máquina (ver /usr/bin/mok-enroll).
#
# Best-effort como 65-secureboot-sign.sh: sem os secrets (forks, PRs
# externas, testes locais), sai sem gerar UKI e a imagem fica só com as
# entradas BLS de sempre. COM os secrets presentes, uma falha aqui É fatal —
# publicar uma imagem com UKI mal assinado deixaria máquinas que já
# migraram para UKI sem arrancar sob Secure Boot.
set -euo pipefail
trap 'printf "\033[1;31mERRO linha %s: %s\033[0m\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

TARGET=/target
OUT_DIR=/uki-out
mkdir -p "$OUT_DIR"

PCR_KEY=/run/secrets/pcr_key
PCR_PUB=/ctx/assets/secureboot/pcr-signing-public.pem
MOK_KEY=/run/secrets/mok_key
MOK_CERT=/ctx/assets/secureboot/MOK.crt

if [[ ! -s "$PCR_KEY" || ! -s "$MOK_KEY" ]]; then
    echo "INFO: secret 'pcr_key' e/ou 'mok_key' não fornecido a este build — a saltar geração do UKI."
    echo "      A imagem fica só com as entradas BLS separadas (kernel+initrd), como hoje."
    exit 0
fi

command -v ukify >/dev/null 2>&1 || { echo "FATAL: ukify ausente (systemd-ukify não instalado neste stage?)"; exit 1; }
command -v sbsign >/dev/null 2>&1 || { echo "FATAL: sbsign ausente (sbsigntools não instalado neste stage?)"; exit 1; }

KVER=$(find "$TARGET/usr/lib/modules" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | sort -V | tail -1)
[[ -n "$KVER" ]] || { echo "FATAL: não foi possível determinar KVER em $TARGET/usr/lib/modules"; exit 1; }
OUTPUT="$OUT_DIR/$KVER.efi"

echo "A compor o UKI para $KVER..."
bootc container ukify --rootfs "$TARGET" -- \
    --pcr-private-key="$PCR_KEY" \
    --pcr-public-key="$PCR_PUB" \
    --phases="enter-initrd enter-initrd:leave-initrd" \
    --secureboot-private-key="$MOK_KEY" \
    --secureboot-certificate="$MOK_CERT" \
    --output="$OUTPUT"

[[ -s "$OUTPUT" ]] || { echo "FATAL: UKI vazio ou ausente após ukify: $OUTPUT"; exit 1; }

sbverify --cert "$MOK_CERT" "$OUTPUT" \
    || { echo "FATAL: assinatura Secure Boot do UKI não validou contra a MOK do projeto"; exit 1; }

echo "✓ UKI assinado (Secure Boot + PCR11 signed policy): $OUTPUT"
