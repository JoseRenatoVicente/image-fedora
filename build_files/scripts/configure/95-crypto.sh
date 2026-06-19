#!/bin/bash
# Crypto policy — DEVE correr por último (antes dos testes): FUTURE rejeita
# RSA-2048, o que bloqueia downloads TLS para muitos servidores. Qualquer passo
# que precise de rede tem de vir ANTES deste.
set -euo pipefail
trap 'printf "\033[1;31mERRO linha %s: %s\033[0m\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

update-crypto-policies --set FUTURE:CHRONY-NTS
