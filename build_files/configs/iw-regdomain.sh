#!/bin/bash
# Set WiFi regulatory domain from the system timezone.
# Uses /usr/share/zoneinfo/zone1970.tab (shipped by tzdata) to map TZ → ISO-3166 country.
set -euo pipefail

[[ -L /etc/localtime ]] || exit 0
command -v iw &>/dev/null || exit 0

TZ=$(readlink /etc/localtime | sed 's|.*/zoneinfo/||')
ZONE_TAB=/usr/share/zoneinfo/zone1970.tab

[[ -f "$ZONE_TAB" ]] || exit 0

# zone1970.tab: <codes>\t<coordinates>\t<TZ name>[\t<comments>]
# First field may be comma-separated for timezones shared by multiple countries.
COUNTRY=$(awk -F'\t' -v tz="$TZ" '$3 == tz { split($1, codes, ","); print codes[1]; exit }' "$ZONE_TAB")

if [[ -n "${COUNTRY:-}" ]]; then
    iw reg set "$COUNTRY"
    echo "iw-regdomain: set to ${COUNTRY} (from ${TZ})"
else
    echo "iw-regdomain: no country mapping found for ${TZ}, skipping"
fi
