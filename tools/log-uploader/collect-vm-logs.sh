#!/usr/bin/env bash
set -euo pipefail

UPLOAD_URL="${1:-${UPLOAD_URL:-}}"
if [[ -z "$UPLOAD_URL" ]]; then
  echo "Uso: $0 http://HOST:3000/upload" >&2
  echo "Ou defina UPLOAD_URL=http://HOST:3000/upload" >&2
  exit 2
fi

command -v curl >/dev/null 2>&1 || { echo "curl não encontrado" >&2; exit 1; }
command -v tar >/dev/null 2>&1 || { echo "tar não encontrado" >&2; exit 1; }

TS="$(date -u +%Y%m%dT%H%M%SZ)"
HOSTNAME_SAFE="$(hostname 2>/dev/null | tr -c 'A-Za-z0-9._-' '_' || echo fedora-vm)"
WORKDIR="$(mktemp -d -t vm-logs.XXXXXX)"
ARCHIVE="/tmp/${HOSTNAME_SAFE}-${TS}-plasma-logs.tar.gz"
trap 'rm -rf "$WORKDIR"' EXIT

run_capture() {
  local name="$1"
  shift
  {
    echo "# command: $*"
    echo "# timestamp: $(date -Is)"
    "$@"
  } >"$WORKDIR/${name}.txt" 2>&1 || true
}

copy_if_exists() {
  local src="$1" dst="$2"
  if [[ -e "$src" ]]; then
    mkdir -p "$(dirname "$WORKDIR/$dst")"
    cp -a "$src" "$WORKDIR/$dst" 2>/dev/null || true
  fi
}

cat >"$WORKDIR/README.txt" <<EOF
VM Plasma diagnostics
Timestamp UTC: $TS
User: ${USER:-unknown}
Home: ${HOME:-unknown}
Upload URL: $UPLOAD_URL
EOF

run_capture journal-plasma-errors journalctl -b --no-pager -o short-iso
run_capture journal-current-user journalctl --user -b --no-pager -o short-iso
run_capture grep-error-loading-applet bash -lc 'journalctl -b --no-pager -o short-iso | grep -iE "error.*loading.*applet|applet.*error" || true'
run_capture system-info bash -lc 'printf "hostname="; hostname; printf "kernel="; uname -a; printf "os-release:\n"; cat /etc/os-release; printf "\nplasma packages:\n"; rpm -qa | grep -Ei "plasma|kwin|kde" | sort'
run_capture appletsrc-focused bash -lc 'grep -nE "^\[Containments\]|^\[Containments\].*Applets|^plugin=|SystrayContainmentId|extraItems=|knownItems=" ~/.config/plasma-org.kde.plasma.desktop-appletsrc 2>/dev/null || true'
run_capture missing-applets bash -lc 'while IFS= read -r plugin; do [ -z "$plugin" ] && continue; [ -d "/usr/share/plasma/plasmoids/$plugin" ] || [ -d "/usr/share/kpackage/genericqml/$plugin" ] || echo "MISSING: $plugin"; done < <(sed -n "s/^plugin=//p" ~/.config/plasma-org.kde.plasma.desktop-appletsrc 2>/dev/null | sort -u)'
run_capture skel-focused bash -lc 'grep -nE "SystrayContainmentId|org\.kde\.plasma\.private\.systemtray|^\[Containments\].*Applets|^plugin=|extraItems=|knownItems=" /etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc 2>/dev/null || true'
run_capture look-and-feel bash -lc 'find /usr/share/plasma/look-and-feel/Mokka ~/.local/share/plasma/look-and-feel/Mokka -maxdepth 4 -type f 2>/dev/null | sort; printf "\n--- defaults ---\n"; cat /usr/share/plasma/look-and-feel/Mokka/contents/defaults 2>/dev/null || true'
run_capture keyd journalctl -b --no-pager -o short-iso -u keyd.service

copy_if_exists "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" "home/.config/plasma-org.kde.plasma.desktop-appletsrc"
copy_if_exists "$HOME/.config/plasmashellrc" "home/.config/plasmashellrc"
copy_if_exists "$HOME/.config/kdeglobals" "home/.config/kdeglobals"
copy_if_exists "$HOME/.config/plasmarc" "home/.config/plasmarc"
copy_if_exists "$HOME/.config/kscreenlockerrc" "home/.config/kscreenlockerrc"
copy_if_exists "/etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc" "etc-skel/.config/plasma-org.kde.plasma.desktop-appletsrc"

tar -C "$WORKDIR" -czf "$ARCHIVE" .

echo "Arquivo gerado: $ARCHIVE"
echo "Enviando para: $UPLOAD_URL"
curl --fail --show-error --location \
  --request POST \
  --header 'content-type: application/gzip' \
  --data-binary "@$ARCHIVE" \
  "${UPLOAD_URL}?name=$(basename "$ARCHIVE")"

echo "Upload concluído."
