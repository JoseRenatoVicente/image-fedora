#!/bin/bash
# Assina o systemd-bootx64.efi (pacote systemd-boot-unsigned) com a MOK do
# projecto, para poder arrancar sob Secure Boot depois de enrolada em cada
# máquina (ver /usr/bin/mok-enroll).
#
# A chave PRIVADA nunca entra na imagem nem no repositório: só existe como
# GitHub Actions secret (MOK_SIGNING_KEY), montada neste RUN via
# --mount=type=secret (ver Containerfile). O certificado PÚBLICO
# (build_files/assets/secureboot/MOK.{crt,der}) é o único material que fica
# no repo — sem ele, mokutil não tem o que importar nas máquinas.
#
# Este script corre ANTES de 70-build-deps.sh (que remove sbsigntools) e é
# best-effort: em builds sem o secret configurado (forks, testes locais, PRs
# externos), o binário fica por assinar e sd-boot-migrate recusa-se a agir —
# não deve abortar a build.
set -euo pipefail
trap 'printf "\033[1;31mERRO linha %s: %s\033[0m\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

EFI_BIN=/usr/lib/systemd/boot/efi/systemd-bootx64.efi
CERT=/ctx/assets/secureboot/MOK.crt
DER=/ctx/assets/secureboot/MOK.der
KEY=/run/secrets/mok_key
PCR_PUB=/ctx/assets/secureboot/pcr-signing-public.pem

# Certificado público: sempre instalado (é preciso para mokutil --import nas
# máquinas, independentemente de este build ter ou não a chave para assinar).
install -Dm644 "$DER" /usr/share/secureboot/MOK.der
setfattr -n user.component -v "security-hardening" /usr/share/secureboot/MOK.der

# Chave pública da PCR signing key: sempre instalada, pelo mesmo motivo — é
# contra ela que tpm2-luks-enroll/tpm2-first-enroll enrolam o LUKS
# (systemd-cryptenroll --tpm2-public-key=...), independentemente de este
# build ter ou não a privada para assinar o UKI (ver build-uki.sh).
install -Dm644 "$PCR_PUB" /usr/share/secureboot/tpm2-pcr-public.pem
setfattr -n user.component -v "security-hardening" /usr/share/secureboot/tpm2-pcr-public.pem

if [[ ! -f "$EFI_BIN" ]]; then
    echo "INFO: $EFI_BIN ausente (systemd-boot-unsigned não instalado?), a saltar assinatura."
    exit 0
fi

if [[ ! -s "$KEY" ]]; then
    echo "INFO: secret 'mok_key' não fornecido a este build — systemd-boot fica por assinar."
    echo "      sd-boot-migrate vai recusar-se a instalá-lo até haver um build assinado."
    exit 0
fi

command -v sbsign >/dev/null 2>&1 || { echo "FATAL: sbsign ausente (sbsigntools não instalado?)"; exit 1; }

echo "A assinar $EFI_BIN com a MOK do projecto..."
sbsign --key "$KEY" --cert "$CERT" --output "$EFI_BIN.signed" "$EFI_BIN"
mv "$EFI_BIN.signed" "$EFI_BIN"
echo "✓ systemd-bootx64.efi assinado."
