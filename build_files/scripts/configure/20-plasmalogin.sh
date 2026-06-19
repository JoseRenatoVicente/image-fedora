#!/bin/bash
# Plasmalogin workaround (from Kinoite): cria as entradas em falta em
# /etc/shadow & /etc/gshadow no primeiro arranque via serviço oneshot.
# Depende do preset 35-security-desktop.preset já copiado pelo 10-system.sh.
set -euo pipefail
trap 'printf "\033[1;31mERRO linha %s: %s\033[0m\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

cat > /usr/lib/systemd/system/fedora-kinoite-plasmalogin-workaround.service << 'EOF'
[Unit]
Description=Workaround for missing plasmalogin entries in /etc/shadow & /etc/gshadow
Documentation=https://forge.fedoraproject.org/kde/tickets/issues/684
ConditionPathIsReadWrite=/etc
ConditionPathExists=/run/ostree-booted
ConditionPathExists=!/etc/.fedora-kinoite-plasmalogin-workaround
Before=plasmalogin.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/libexec/fedora-kinoite-plasmalogin-workaround

[Install]
WantedBy=multi-user.target
EOF

cat > /usr/libexec/fedora-kinoite-plasmalogin-workaround << 'SCRIPT'
#!/bin/bash
set -euo pipefail

echo "Checking plasmalogin entries in /etc/shadow & /etc/gshadow"

if [[ $(grep -c "plasmalogin" "/etc/shadow") -eq 0 ]]; then
    echo "plasmalogin:!*:::::::" >> "/etc/shadow"
    echo "Added missing plasmalogin entry to /etc/shadow"
else
    echo "Nothing to do for /etc/shadow"
fi

if [[ $(grep -c "plasmalogin" "/etc/gshadow") -eq 0 ]]; then
    echo "plasmalogin:!*::" >> "/etc/gshadow"
    echo "Added missing plasmalogin entry to /etc/gshadow"
else
    echo "Nothing to do for /etc/gshadow"
fi

echo "Writing stamp file: /etc/.fedora-kinoite-plasmalogin-workaround"
touch /etc/.fedora-kinoite-plasmalogin-workaround
SCRIPT

chmod a+x /usr/libexec/fedora-kinoite-plasmalogin-workaround

cat >> /usr/lib/systemd/system-preset/35-security-desktop.preset << 'EOF'

# Plasmalogin workaround (from Kinoite)
enable fedora-kinoite-plasmalogin-workaround.service
EOF

systemctl preset fedora-kinoite-plasmalogin-workaround.service
