#!/usr/bin/bash
echo "::group:: ===$(basename "$0")==="
set -euox pipefail

IMAGE_NAME="${IMAGE_NAME:-fedora}"
IMAGE_PRETTY_NAME="${IMAGE_PRETTY_NAME:-Fedora}"
IMAGE_VENDOR="${IMAGE_VENDOR:-}"
SHA_HEAD_SHORT="${SHA_HEAD_SHORT:-}"

IMAGE_INFO="/usr/share/image-info.json"
mkdir -p "$(dirname "$IMAGE_INFO")"

cat > "$IMAGE_INFO" << EOF
{
  "image-name": "${IMAGE_NAME}",
  "image-vendor": "${IMAGE_VENDOR:-custom}",
  "base-image-name": "base-atomic",
  "fedora-version": "$(rpm -E %fedora)"
}
EOF

# Personalizar /usr/lib/os-release para que neofetch/fastfetch mostrem
# o nome correcto em vez de "Fedora Linux".
sed -i "s|^NAME=.*|NAME=\"${IMAGE_PRETTY_NAME}\"|" /usr/lib/os-release
sed -i "s|^PRETTY_NAME=.*|PRETTY_NAME=\"${IMAGE_PRETTY_NAME}\"|" /usr/lib/os-release
sed -i "s|^VARIANT_ID=.*|VARIANT_ID=${IMAGE_NAME}|" /usr/lib/os-release
sed -i "s|^DEFAULT_HOSTNAME=.*|DEFAULT_HOSTNAME=\"${IMAGE_NAME}\"|" /usr/lib/os-release

if [[ -n "${SHA_HEAD_SHORT}" ]]; then
    echo "BUILD_ID=\"${SHA_HEAD_SHORT}\"" >> /usr/lib/os-release
fi

# IMAGE_REF lets the software store (cosmic-store) find the correct registry for update checks.
# Only set when IMAGE_VENDOR is known (i.e. CI builds pushed to ghcr.io).
if [[ -n "${IMAGE_VENDOR}" ]]; then
    echo "IMAGE_REF=\"ostree-image-signed:docker://ghcr.io/${IMAGE_VENDOR}/${IMAGE_NAME}\"" \
        >> /usr/lib/os-release
fi

cat /usr/lib/os-release

echo "::endgroup::"
