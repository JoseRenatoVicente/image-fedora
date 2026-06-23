#!/bin/bash
# Cleanup final: limpa caches dnf, estado /var, docs/man/info e locales
# (mantém apenas pt_BR e en_US). Alinhado com "zero baked /var state".
set -euo pipefail
trap 'printf "\033[1;31mERRO linha %s: %s\033[0m\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

dnf5 clean all
rm -rf /var/cache/dnf /var/log/dnf* /var/log/hawkey*
rm -rf /run/* /tmp/* 2>/dev/null || true
rm -rf /var/lib/dnf/repos /var/lib/dnf/*.lock 2>/dev/null || true
rm -rf /var/lib/flatpak 2>/dev/null || true
rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/info/*
LOCALE_REMOVED=0
while IFS= read -r -d '' dir; do
    rm -rf "$dir" && ((++LOCALE_REMOVED))
done < <(find /usr/share/locale -mindepth 1 -maxdepth 1 \
    ! -name 'pt_BR' ! -name 'en_US' ! -name 'locale.alias' \
    -print0)
echo "Locales removidos: $LOCALE_REMOVED (mantidos: pt_BR, en_US)"
printf 'LANG=pt_BR.UTF-8\n' > /etc/locale.conf
ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime
printf 'America/Sao_Paulo\n' > /etc/timezone

# Regenerar cache do linker após todas as alterações ao /usr
ldconfig
