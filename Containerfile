# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /

# Build-time metadata (passável via --build-arg)
ARG IMAGE_NAME="fedora"
ARG IMAGE_PRETTY_NAME="Fedora"
ARG IMAGE_VENDOR=""
ARG SHA_HEAD_SHORT=""
ARG SOURCE_DATE_EPOCH=""

# Base Image
FROM quay.io/fedora-ostree-desktops/base-atomic:44

ARG IMAGE_NAME="fedora"
ARG IMAGE_PRETTY_NAME="Fedora"
ARG IMAGE_VENDOR=""
ARG SHA_HEAD_SHORT=""
ARG SOURCE_DATE_EPOCH=""

## Other possible base images include:
# FROM quay.io/fedora-ostree-desktops/kinoite:44  (full KDE, ~7.1 GB)
# FROM ghcr.io/ublue-os/bazzite:latest
# FROM ghcr.io/ublue-os/bluefin-nvidia:stable
# 
# ... and so on, here are more base images
# Universal Blue Images: https://github.com/orgs/ublue-os/packages
# Fedora base image: quay.io/fedora/fedora-bootc:41
# CentOS base images: quay.io/centos-bootc/centos-bootc:stream10

### [IM]MUTABLE /opt
## Some bootable images, like Fedora, have /opt symlinked to /var/opt, in order to
## make it mutable/writable for users. However, some packages write files to this directory,
## thus its contents might be wiped out when bootc deploys an image, making it troublesome for
## some packages. Eg, google-chrome, docker-desktop.
##
## Uncomment the following line if one desires to make /opt immutable and be able to be used
## by the package manager.

RUN [[ -L /opt ]] && rm /opt && mkdir /opt || true

### MODIFICATIONS
## make modifications desired in your image and install packages by modifying the build.sh script
## the following RUN directive does all the things required to run "build.sh" as recommended.

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    IMAGE_NAME="${IMAGE_NAME}" \
    IMAGE_PRETTY_NAME="${IMAGE_PRETTY_NAME}" \
    IMAGE_VENDOR="${IMAGE_VENDOR}" \
    SHA_HEAD_SHORT="${SHA_HEAD_SHORT}" \
    SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH}" \
    /ctx/build.sh
    
### LINTING
## Verify final image and contents are correct.
RUN bootc container lint
