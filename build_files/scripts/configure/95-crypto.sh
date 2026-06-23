#!/bin/bash
# Crypto policy — DEFAULT mantém compatibilidade TLS para DNF/librepo/curl.
# CHRONY-NTS preserva a exceção necessária para servidores NTS com RSA-2048.
set -euo pipefail
trap 'printf "\033[1;31mERRO linha %s: %s\033[0m\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

update-crypto-policies --set DEFAULT:CHRONY-NTS
