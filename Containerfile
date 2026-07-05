# Todos os ficheiros de build — usados pelo Layer 2 (configure)
FROM scratch AS ctx
COPY build_files /

# Sub-stage com apenas os ficheiros que afectam instalação de pacotes.
# O Layer 1 só invalida o cache quando ESTES ficheiros mudam — alterações
# a configs/skel/theming não tocam este stage e não re-correm o dnf.
FROM scratch AS ctx-pkgs
COPY build_files/scripts/build-packages.sh /build-packages.sh
COPY build_files/scripts/shared/copr-helpers.sh /shared/copr-helpers.sh
COPY build_files/scripts/shared/common.sh /shared/common.sh
COPY build_files/scripts/shared/package-lists.sh /shared/package-lists.sh
COPY build_files/assets/configs/dnf-performance.conf /configs/dnf-performance.conf

# Build-time metadata (passável via --build-arg)
ARG IMAGE_NAME="fedora"
ARG IMAGE_PRETTY_NAME="Fedora"
ARG IMAGE_VENDOR=""
ARG SHA_HEAD_SHORT=""
ARG SOURCE_DATE_EPOCH=""
ARG PKG_CACHE_KEY=""
ARG CONFIG_CACHE_KEY=""

# Base Image
FROM quay.io/fedora-ostree-desktops/base-atomic:44@sha256:6856041720a8a506343df50b357f0e643801a8cc10e092fd5ac2024031fc5d34

ARG IMAGE_NAME="fedora"
ARG IMAGE_PRETTY_NAME="Fedora"
ARG IMAGE_VENDOR=""
ARG SHA_HEAD_SHORT=""
ARG SOURCE_DATE_EPOCH=""
ARG PKG_CACHE_KEY=""
ARG CONFIG_CACHE_KEY=""

RUN [[ -L /opt ]] && rm /opt && mkdir /opt || true

# ── Layer 1: Pacotes dnf + COPR ───────────────────────────────────────────────
# Cache estável: só invalida quando build-packages.sh, copr-helpers.sh ou
# dnf-performance.conf mudam (i.e., quando a lista de pacotes muda).
# Alterações a configs/skel/theming não chegam a este stage → cache hit.
LABEL org.image-fedora.pkg-cache-key="${PKG_CACHE_KEY}"
RUN --mount=type=bind,from=ctx-pkgs,source=/,target=/ctx-pkgs \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx-pkgs/build-packages.sh

# ── Layer 2: Configuração, theming, skel, dracut ──────────────────────────────
# Cache invalida em qualquer mudança a build_files/ — mas este layer é rápido
# (~2-3 min) porque não corre dnf install na maioria dos commits.
LABEL org.image-fedora.config-cache-key="${CONFIG_CACHE_KEY}"
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    --mount=type=secret,id=mok_key,target=/run/secrets/mok_key \
    IMAGE_NAME="${IMAGE_NAME}" \
    IMAGE_PRETTY_NAME="${IMAGE_PRETTY_NAME}" \
    IMAGE_VENDOR="${IMAGE_VENDOR}" \
    SHA_HEAD_SHORT="${SHA_HEAD_SHORT}" \
    SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH}" \
    /ctx/scripts/build-configure.sh

RUN bootc container lint
