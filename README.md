# Fedora KDE Secure Dev Image

Custom Fedora bootc image (KDE Plasma on the minimal `base-atomic` base) for a secure development workstation.

The image keeps the base OS focused on boot, security hardening, KDE integration, container workflow support, and hardware/security-key support. Development stacks and user applications should live in Flatpak, Distrobox, Toolbox, or user-scoped setup instead of being layered into the immutable base.

## Atomic Model

- The base OS is delivered as a bootc-compatible OCI image and updated transactionally.
- Runtime package mutation with `dnf` is intentionally discouraged; `/usr/bin/dnf` is wrapped to point users toward Atomic workflows.
- Use `rpm-ostree install <package>` only for rare host-level layering that truly belongs in the base deployment.
- Use Flatpak for GUI applications.
- Use Distrobox or Toolbox for language runtimes, build tools, Kubernetes/Terraform CLIs, and per-project dependencies.

## Base OS Contents

- Fedora `base-atomic` bootc base pinned by digest in `Containerfile`, with a minimal KDE Plasma install layered on top.
- SELinux enforcing configuration.
- Firewalld, hardened sysctl settings, bootc kernel arguments, coredump restrictions, and module blacklists.
- Podman, Distrobox, Podman Compose, and Docker-compatible Podman wrappers for container workflows.
- KDE/Plasma defaults, theme assets, SDDM configuration, and desktop integration.
- YubiKey/U2F packages and PAM support for security keys.
- Small recovery and productivity CLI tools such as `git`, `curl`, `jq`, `ripgrep`, `fd`, `bat`, `eza`, and `neovim`.

## Development Workflow

On first boot, per-user systemd services and timers (`fedora-flatpak-setup`, `fedora-shell-setup`, `fedora-dev-setup`, `fedora-brew-setup`, installed via `/etc/skel`) run automatically to install user-scoped Flatpaks, shell conveniences (Oh My Zsh / zsh), NVM/Node.js, and Homebrew.

Prefer a per-project development container for toolchains:

```bash
distrobox create --name dev --image registry.fedoraproject.org/fedora-toolbox:44
```

Install high-churn tools such as Node packages, Terraform, Kubernetes CLIs, language servers, compilers, and SDKs inside the project container unless they are needed by the host itself.

## Build And Test

Build the container image:

```bash
just build
```

Run static tests against a built local image:

```bash
just test-container
```

Run source-level policy tests (BATS):

```bash
just validate-source   # runs: bats tests/source/
```

Build a QCOW2 disk image:

```bash
just build-qcow2
```

Local disk-image builds use `bootc-image-builder` in a privileged container and mount container storage. Treat that command as a trusted local build step, not as an unprivileged sandbox.

## Supply Chain

- CI verifies the real Fedora `base-atomic` base image signature, ignoring the `scratch` build-context stage.
- Published images are signed with keyless Cosign using GitHub Actions OIDC.
- CI generates and publishes SBOM/provenance artifacts.
- `bootc-image-builder` is pinned by digest for local and CI disk-image builds.
- Third-party package repos should remain disabled or absent from the final base unless explicitly required.

Verify a published image signature:

```bash
cosign verify ghcr.io/<owner>/<image>:latest \
  --certificate-identity-regexp 'https://github.com/.+' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com'
```

Verify provenance:

```bash
cosign verify-attestation ghcr.io/<owner>/<image>:latest \
  --certificate-identity-regexp 'https://github.com/.+' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
  --type slsaprovenance
```

## Updates

`rpm-ostreed-automatic.timer` is enabled by default so installed systems receive Atomic updates automatically.

Disable automatic rpm-ostree updates if you need manual rollout control:

```bash
sudo systemctl disable --now rpm-ostreed-automatic.timer
```

Podman auto-update is also enabled for containers that opt in through their labels.

## Security Defaults

- Bluetooth is not enabled by default in the secure profile. Enable it manually if your hardware workflow requires it.
- SELinux is configured for enforcing mode.
- Core dumps are disabled through systemd and limits configuration.
- Firewalld is enabled by default.
- Kernel arguments are installed through `/usr/lib/bootc/kargs.d/10-hardening.toml`.

## Repository Layout

- `Containerfile`: bootc image definition and build entrypoint (two cached layers: packages, then configuration).
- `build_files/scripts/`: build logic — `build-packages.sh` (Layer 1: dnf/COPR), `build-configure.sh` (Layer 2 driver), `configure/` (numbered configuration modules), and `shared/` (helpers, `package-lists.sh`, in-build `tests.sh`).
- `build_files/overlay/`: filesystem tree (`etc/`, `usr/`) overlaid onto the image as-is.
- `build_files/assets/`: build-time inputs — `assets-manifest.sh` (themes/fonts with pinned checksums), `configs/`, and `selinux/` CIL policies.
- `build_files/skel/`: default user files copied through `/etc/skel`.
- `build_files/test/`: local-only boot-test helpers (see `Containerfile.test`).
- `disk_config/`: bootc-image-builder disk and ISO configuration.
- `.github/workflows/`: CI, image publication, scanning, signing, and disk-image workflows.
- `tests/source/` and `tests/container/`: source-level (BATS, pre-build) and container (post-build) policy tests.
