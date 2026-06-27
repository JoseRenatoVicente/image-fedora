#!/bin/bash
# Plasmalogin workaround (from Kinoite): aplica o preset do serviço oneshot.
# A unit e o helper são arquivos estáticos vindos do overlay.
set -euo pipefail
trap 'printf "\033[1;31mERRO linha %s: %s\033[0m\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

systemctl preset fedora-kinoite-plasmalogin-workaround.service
