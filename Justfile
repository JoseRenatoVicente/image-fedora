export image_name := env("IMAGE_NAME", "fedora-kde-custom") # output image name, usually same as repo name, change as needed
export image_vendor := env("IMAGE_VENDOR", env("GITHUB_REPOSITORY_OWNER", "")) # ghcr.io owner; auto-detected in CI
export default_tag := env("DEFAULT_TAG", "latest")
export bib_image := env("BIB_IMAGE", "quay.io/centos-bootc/bootc-image-builder@sha256:7ae88b8d6f2cabfa971d7836b96d6cac19cd1384e658031bd154f9687e929905")

# Cosign: identidades confiáveis para verificação (não aceitar qualquer repo GitHub).
# Assinatura da imagem → workflow build.yml do dono do repo; provenance → slsa-github-generator.
sign_oidc_issuer := "https://token.actions.githubusercontent.com"
sign_identity := "^https://github.com/" + env("GITHUB_REPOSITORY_OWNER", env("USER", "local")) + "/[^/]+/.github/workflows/build.yml@refs/heads/"
provenance_identity := "^https://github.com/slsa-framework/slsa-github-generator/.github/workflows/generator_container_slsa3.yml@refs/tags/v"

alias build-vm := build-qcow2
alias rebuild-vm := rebuild-qcow2
alias run-vm := run-vm-qcow2
alias test := test-container

import 'just/utility.just'
import 'just/build.just'
import 'just/vm.just'
import 'just/security.just'
import 'just/testing.just'

[private]
default:
    @just --list
