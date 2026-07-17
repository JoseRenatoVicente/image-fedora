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
ARCHIVE="/tmp/${HOSTNAME_SAFE}-${TS}-cosmic-logs.tar.gz"
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
VM COSMIC diagnostics
Timestamp UTC: $TS
User: ${USER:-unknown}
Home: ${HOME:-unknown}
Upload URL: $UPLOAD_URL
EOF

run_capture journal-boot-errors journalctl -b --no-pager -o short-iso
run_capture journal-current-user journalctl --user -b --no-pager -o short-iso
run_capture journal-cosmic-session bash -lc 'journalctl -b --no-pager -o short-iso -u cosmic-greeter.service --user -u cosmic-session 2>/dev/null || true'
run_capture system-info bash -lc 'printf "hostname="; hostname; printf "kernel="; uname -a; printf "os-release:\n"; cat /etc/os-release; printf "\ncosmic packages:\n"; rpm -qa | grep -Ei "cosmic|greetd" | sort'
run_capture cosmic-theme bash -lc 'for d in /usr/share/cosmic/com.system76.CosmicTheme.Dark /usr/share/cosmic/com.system76.CosmicTheme.Dark.Builder; do echo "--- $d ---"; cat "$d/v1/name" 2>/dev/null; echo; cat "$d/v1/palette" 2>/dev/null | head -5; echo; done'
run_capture keyd journalctl -b --no-pager -o short-iso -u keyd.service

copy_if_exists "$HOME/.config/cosmic" "home/.config/cosmic"

tar -C "$WORKDIR" -czf "$ARCHIVE" .

echo "Arquivo gerado: $ARCHIVE"
echo "Enviando para: $UPLOAD_URL"
curl --fail --show-error --location \
  --request POST \
  --header 'content-type: application/gzip' \
  --data-binary "@$ARCHIVE" \
  "${UPLOAD_URL}?name=$(basename "$ARCHIVE")"

echo "Upload concluído."
