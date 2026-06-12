# image-template

This repository is meant to be a template for building your own custom [bootc](https://github.com/bootc-dev/bootc) image. This template is the recommended way to make customizations to any image published by the Universal Blue Project.

# Community

If you have questions about this template after following the instructions, try the following spaces:
- [Universal Blue Forums](https://universal-blue.discourse.group/)
- [Universal Blue Discord](https://discord.gg/WEu6BdFEtp)
- [bootc discussion forums](https://github.com/bootc-dev/bootc/discussions) - This is not an Universal Blue managed space, but is an excellent resource if you run into issues with building bootc images.

# How to Use

To get started on your first bootc image, simply read and follow the steps in the next few headings.
If you prefer instructions in video form, TesterTech created an excellent tutorial, embedded below.

[![Video Tutorial](https://img.youtube.com/vi/IxBl11Zmq5w/0.jpg)](https://www.youtube.com/watch?v=IxBl11Zmq5wE)

## Step 0: Prerequisites

These steps assume you have the following:
- A Github Account
- A machine running a bootc image (e.g. Bazzite, Bluefin, Aurora, or Fedora Atomic)
- Experience installing and using CLI programs

## Step 1: Preparing the Template

### Step 1a: Copying the Template

Select `Use this Template` on this page. You can set the name and description of your repository to whatever you would like, but all other settings should be left untouched.

Once you have finished copying the template, you need to enable the Github Actions workflows for your new repository.
To enable the workflows, go to the `Actions` tab of the new repository and click the button to enable workflows.

### Step 1b: Cloning the New Repository

Here I will defer to the much superior GitHub documentation on the matter. You can use whichever method is easiest.
[GitHub Documentation](https://docs.github.com/en/repositories/creating-and-managing-repositories/cloning-a-repository)

Once you have the repository on your local drive, proceed to the next step.

## Step 2: Initial Setup

### Step 2a: Cosign Setup

This repository signs published images in GitHub Actions using keyless Sigstore identities tied to the workflow OIDC token. No `SIGNING_SECRET` is required for the default CI path.

Install the [cosign CLI tool](https://edu.chainguard.dev/open-source/sigstore/cosign/how-to-install-cosign/#installing-cosign-with-the-cosign-binary) if you want to verify the published image locally or use the optional local key-based signing flow.

For optional local signing only, generate a key pair inside your repo folder:

```bash
COSIGN_PASSWORD="" cosign generate-key-pair
```

The local key pair is only used by `just sign-local` and `just verify-local-signature`. It will not be used by the default GitHub Actions release path.

> [!WARNING]
> Be careful to *never* accidentally commit `cosign.key` into your git repo. If this key goes out to the public, the security of your repository is compromised.

You do not need to add this key to GitHub for the default CI flow. Keep the key pair only if you want local signing by digest.

To verify a published image after CI:

```bash
cosign verify ghcr.io/<username>/<image_name>:latest \
  --certificate-identity-regexp 'https://github.com/.+' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com'
```

To verify provenance:

```bash
cosign verify-attestation ghcr.io/<username>/<image_name>:latest \
  --certificate-identity-regexp 'https://github.com/.+' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
  --type slsaprovenance
```

### Step 2b: Choosing Your Base Image

To choose a base image, simply modify the line in the container file starting with `FROM`. This will be the image your image derives from, and is your starting point for modifications.
For a base image, you can choose any of the Universal Blue images or start from a Fedora Atomic system. Below this paragraph is a dropdown with a non-exhaustive list of potential base images.

<details>
    <summary>Base Images</summary>

- Bazzite: `ghcr.io/ublue-os/bazzite:stable`
- Aurora: `ghcr.io/ublue-os/aurora:stable`
- Bluefin: `ghcr.io/ublue-os/bluefin:stable`
- Universal Blue Base: `ghcr.io/ublue-os/base-main:latest`
- Fedora: `quay.io/fedora/fedora-bootc:42`

You can find more Universal Blue images on the [packages page](https://github.com/orgs/ublue-os/packages).
</details>

If you don't know which image to pick, choosing the one your system is currently on is the best bet for a smooth transition. To find out what image your system currently uses, run the following command:
```bash
sudo bootc status
```
This will show you all the info you need to know about your current image. The image you are currently on is displayed after `Booted image:`. Paste that information after the `FROM` statement in the Containerfile to set it as your base image.

### Step 2c: Changing Names

Change the first line in the [Justfile](./Justfile) to your image's name.

To commit and push all the files changed and added in step 2 into your Github repository:
```bash
git add Containerfile Justfile cosign.pub
git commit -m "Initial Setup"
git push
```
Once pushed, go look at the Actions tab on your Github repository's page.  The green checkmark should be showing on the top commit, which means your new image is ready!

## Step 3: Switch to Your Image

From your bootc system, run the following command substituting in your Github username and image name where noted.
```bash
sudo bootc switch ghcr.io/<username>/<image_name>
```
This should queue your image for the next reboot, which you can do immediately after the command finishes. You have officially set up your custom image! See the following section for an explanation of the important parts of the template for customization.

# Pre-installed Tools

## Claude Code

This image comes with **Claude Code** pre-installed and ready to use. Claude Code is Anthropic's agentic CLI tool that brings Claude's capabilities to your terminal.

Once you boot the image, you can use Claude Code immediately:

```bash
claude --help
```

To authenticate and start using Claude Code:

```bash
claude
```

The tool is installed system-wide via the official Anthropic install script (`https://claude.ai/install.sh`), ensuring you always have the latest version compatible with your system. For more information, visit the [Claude Code documentation](https://code.claude.com/docs).

## Initial User Setup (First Login)

On first login, the image will prompt you to run an interactive setup script that installs additional developer tools:

```
╔════════════════════════════════════════════════════════════════╗
║                 🚀 Fedora KDE Initial Setup                    ║
║                                                                ║
║  Instala: NVM/Node.js, Oh My Zsh, Powerlevel10k, LazyDocker,  ║
║           Homebrew, terraform, kubectl, flux, talosctl        ║
║           Flatpaks (Discord, Telegram, Steam, Chrome, etc)   ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝

  Executar setup agora? [S/n]
```

**Options:**
- **S (default)**: Runs the setup interactively. You can accept/skip each section with prompts
- **n**: Skips setup. You can run it manually later with `bash ~/setup-user.sh`

The setup runs via a systemd user service (`fedora-setup.service`) and asks only once. If you skip, you can always run the setup manually:

```bash
bash ~/setup-user.sh
```

State is tracked in `~/.local/share/fedora-kde-setup/`, so you can re-run individual sections by deleting the corresponding state file.

# Repository Contents

## Containerfile

The [Containerfile](./Containerfile) defines the operations used to customize the selected image.This file is the entrypoint for your image build, and works exactly like a regular podman Containerfile. For reference, please see the [Podman Documentation](https://docs.podman.io/en/latest/Introduction.html).

## build.sh

The [build.sh](./build_files/build.sh) file is called from your Containerfile. It is the best place to install new packages or make any other customization to your system. There are customization examples contained within it for your perusal.

## build.yml

The [build.yml](./.github/workflows/build.yml) Github Actions workflow creates your custom OCI image and publishes it to the Github Container Registry (GHCR). By default, the image name will match the Github repository name. There are several environment variables at the start of the workflow which may be of interest to change.

# Building Disk Images

This template provides an out of the box workflow for creating disk images (ISO, qcow, raw) for your custom OCI image which can be used to directly install onto your machines.

This template provides a way to upload the disk images that is generated from the workflow to a S3 bucket. The disk images will also be available as an artifact from the job, if you wish to use an alternate provider. To upload to S3 we use [rclone](https://rclone.org/) which is able to use [many S3 providers](https://rclone.org/s3/).

## Setting Up ISO Builds

The [build-disk.yml](./.github/workflows/build-disk.yml) Github Actions workflow creates a disk image from your OCI image by utilizing the [bootc-image-builder](https://osbuild.org/docs/bootc/). In order to use this workflow you must complete the following steps:

1. Modify `disk_config/iso.toml` to point to your custom container image before generating an ISO image.
2. If you changed your image name from the default in `build.yml` then in the `build-disk.yml` file edit the `IMAGE_REGISTRY`, `IMAGE_NAME` and `DEFAULT_TAG` environment variables with the correct values. If you did not make changes, skip this step.
3. Finally, if you want to upload your disk images to S3 then you will need to add your S3 configuration to the repository's Action secrets. This can be found by going to your repository settings, under `Secrets and Variables` -> `Actions`. You will need to add the following
  - `S3_PROVIDER` - Must match one of the values from the [supported list](https://rclone.org/s3/)
  - `S3_BUCKET_NAME` - Your unique bucket name
  - `S3_ACCESS_KEY_ID` - It is recommended that you make a separate key just for this workflow
  - `S3_SECRET_ACCESS_KEY` - See above.
  - `S3_REGION` - The region your bucket lives in. If you do not know then set this value to `auto`.
  - `S3_ENDPOINT` - This value will be specific to the bucket as well.

Once the workflow is done, you'll find the disk images either in your S3 bucket or as part of the summary under `Artifacts` after the workflow is completed.

# Artifacthub

This template comes with the necessary tooling to index your image on [artifacthub.io](https://artifacthub.io). Use the `artifacthub-repo.yml` file at the root to verify yourself as the publisher. This is important to you for a few reasons:

- The value of artifacthub is it's one place for people to index their custom images, and since we depend on each other to learn, it helps grow the community. 
- You get to see your pet project listed with the other cool projects in Cloud Native.
- Since the site puts your README front and center, it's a good way to learn how to write a good README, learn some marketing, finding your audience, etc. 

[Discussion Thread](https://universal-blue.discourse.group/t/listing-your-custom-image-on-artifacthub/6446)

# Justfile Documentation

The `Justfile` contains various commands and configurations for building and managing container images and virtual machine images using Podman and other utilities.
To use it, you must have installed [just](https://just.systems/man/en/introduction.html) from your package manager or manually. It is available by default on all Universal Blue images.

## Environment Variables

- `image_name`: The name of the image (default: "image-template").
- `default_tag`: The default tag for the image (default: "latest").
- `bib_image`: The Bootc Image Builder (BIB) image (default: "quay.io/centos-bootc/bootc-image-builder:latest").

## Building The Image

### `just build`

Builds a container image using Podman.

```bash
just build $target_image $tag
```

Arguments:
- `$target_image`: The tag you want to apply to the image (default: `$image_name`).
- `$tag`: The tag for the image (default: `$default_tag`).

## Secure Local Workflow

This repository supports a local-first hardening and release flow. The intended secure path is:

```bash
just build
just audit-security
just audit-package-surface
just audit-supply-chain
just verify-remote-image
just push-local
just sign-local
just verify-local-signature
just promote-local
just run-vm-qcow2
```

Notes:

- `just audit-security` checks image-side hardening markers such as SELinux config, crypto policy `FUTURE`, and the existing hardening files.
- `just audit-package-surface` fails if forbidden packages reappear in the final image.
- `just audit-supply-chain` verifies the published image signature, provenance attestation, and attached SBOM.
- `just verify-remote-image` is the downstream-consumer verification shortcut for the published image.
- `just sign-local` uses `cosign.key` and signs the pushed image by digest.
- `just verify-local-signature` verifies the pushed image with `cosign.pub`.
- `just promote-local` chains build -> audit -> push -> sign -> verify and then verifies the remote published image.

## Verifying Published Images

The CI pipeline publishes a signed image, SLSA provenance, and an attached SBOM. Consumers can verify the published image with:

```bash
just verify-remote-image
```

Or directly with `cosign`:

```bash
cosign verify ghcr.io/<username>/<image_name>:latest \
  --certificate-identity-regexp 'https://github.com/.+' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com'

cosign verify-attestation ghcr.io/<username>/<image_name>:latest \
  --certificate-identity-regexp 'https://github.com/.+' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
  --type slsaprovenance

cosign download sbom ghcr.io/<username>/<image_name>:latest > published-sbom.spdx.json
```

Runtime validation remains separate from image inspection:

- confirm `SELinux=enforcing` from the booted VM
- confirm FIPS is active from the booted VM
- use `just run-vm-qcow2` for the final runtime check

## Building and Running Virtual Machines and ISOs

The below commands all build QCOW2 images. To produce or use a different type of image, substitute in the command with that type in the place of `qcow2`. The available types are `qcow2`, `iso`, and `raw`.

### `just build-qcow2`

Builds a QCOW2 virtual machine image.

```bash
just build-qcow2 $target_image $tag
```

### `just rebuild-qcow2`

Rebuilds a QCOW2 virtual machine image.

```bash
just rebuild-vm $target_image $tag
```

### `just run-vm-qcow2`

Runs a virtual machine from a QCOW2 image.

```bash
just run-vm-qcow2 $target_image $tag
```

### `just spawn-vm`

Runs a virtual machine using systemd-vmspawn.

```bash
just spawn-vm rebuild="0" type="qcow2" ram="6G"
```

## File Management

### `just check`

Checks the syntax of all `.just` files and the `Justfile`.

### `just fix`

Fixes the syntax of all `.just` files and the `Justfile`.

### `just clean`

Cleans the repository by removing build artifacts.

### `just lint`

Runs shell check on all Bash scripts.

### `just format`

Runs shfmt on all Bash scripts.

## Additional resources

For additional driver support, ublue maintains a set of scripts and container images available at [ublue-akmod](https://github.com/ublue-os/akmods). These images include the necessary scripts to install multiple kernel drivers within the container (Nvidia, OpenRazer, Framework...). The documentation provides guidance on how to properly integrate these drivers into your container image.

# Hardening: What Is Disabled and How to Re-enable

This image ships with aggressive security hardening derived from [secureblue](https://github.com/secureblue/secureblue). Below is a summary of what is restricted and how to restore functionality if needed.

## Printing (CUPS)

**Disabled:** `cups.service`, `cups.socket`, `cups.path`, `cups-browsed.service`

Printing is completely non-functional by default.

```bash
sudo systemctl enable --now cups.socket cups.path
# For network printer auto-discovery:
sudo systemctl enable --now cups-browsed.service
```

## Network Discovery (Avahi / mDNS)

**Disabled:** `avahi-daemon.service`, `avahi-daemon.socket`, LLMNR (`resolved`)

Automatic discovery of network printers, Chromecasts, AirPlay devices, and `.local` hostnames will not work.

```bash
sudo systemctl enable --now avahi-daemon.socket
# For LLMNR (Windows-centric networks), edit:
#   /etc/systemd/resolved.conf.d/10-disable-llmnr.conf
# and set LLMNR=resolve or LLMNR=yes
```

## SSH Server

**Disabled:** `sshd.service`, `sshd.socket`, kernel arg `systemd.ssh_auto=no`

The machine cannot be accessed remotely via SSH. Outbound SSH connections (client) work normally.

```bash
sudo systemctl enable --now sshd.socket
```

## Network File Shares (NFS / CIFS / Samba)

**Blocked:** Kernel modules `nfs`, `nfsv3`, `nfsv4`, `cifs`, `ksmbd` via `modprobe -d`

Cannot mount NFS or Samba shares. To re-enable:

```bash
# Create override for the specific module you need:
echo 'install cifs /sbin/modprobe --ignore-install cifs' | sudo tee /etc/modprobe.d/allow-cifs.conf
echo 'install nfsv4 /sbin/modprobe --ignore-install nfsv4' | sudo tee /etc/modprobe.d/allow-nfs.conf
sudo depmod -a
```

## Thunderbolt

**Blocked:** Kernel module `thunderbolt` via `modprobe -d`

Thunderbolt docks, eGPUs, displays, and storage devices will not work. IOMMU is also set to strict mode.

```bash
echo 'install thunderbolt /sbin/modprobe --ignore-install thunderbolt' | sudo tee /etc/modprobe.d/allow-thunderbolt.conf
sudo depmod -a
```

## VPN (IPSec) -- Optional Restriction

**NOT blocked by default.** An optional blacklist is available at `/usr/share/fedora-hardening/modprobe-ipsec-blacklist.conf`. If you activated it and need to revert:

```bash
sudo rm /etc/modprobe.d/modprobe-ipsec-blacklist.conf
sudo reboot
```

## Firewall (All Inbound Blocked)

The default firewall zone has **zero allowed inbound services** (standard Fedora allows `dhcpv6-client`, `mdns`, `sshd`). This blocks KDE Connect, Syncthing, local dev servers, etc.

```bash
# Allow specific services:
sudo firewall-cmd --permanent --add-service=ssh
sudo firewall-cmd --permanent --add-service=mdns
sudo firewall-cmd --permanent --add-service=kdeconnect
sudo firewall-cmd --reload
```

## DVD / Blu-ray (UDF Filesystem)

**Blocked:** Kernel module `udf` via `modprobe -d`

UDF-formatted media (most DVDs and Blu-ray discs) cannot be read.

```bash
echo 'install udf /sbin/modprobe --ignore-install udf' | sudo tee /etc/modprobe.d/allow-udf.conf
sudo depmod -a
```

## Mobile Broadband (ModemManager)

**Disabled:** `ModemManager.service`

4G/5G USB dongles and built-in WWAN cards will not be managed.

```bash
sudo systemctl enable --now ModemManager.service
```

## Geolocation

**Disabled:** `geoclue.service`

Automatic timezone detection and location-based Night Color scheduling will not work.

```bash
sudo systemctl enable --now geoclue.service
```

## FIPS Mode (Not Enabled)

FIPS mode (`fips=1` kernel arg + `dracut-fips` package) is **not enabled** in this image. Enabling FIPS requires careful integration with dracut, kernel HMAC validation, and testing. The `crypto-policies FUTURE` policy already enforces strong cryptographic standards without the boot-time complexity of FIPS.

## Kernel Module Signing (`module.sig_enforce=1`)

Only signed kernel modules can load. Fedora-packaged drivers (including `kmod-nvidia`) work normally. Custom DKMS modules will be rejected. This is expected behavior for an atomic/immutable system -- use `rpm-ostree install` for signed driver packages.

## Kernel Lockdown (`lockdown=integrity`)

Prevents modification of the running kernel. Blocks `/dev/mem` access, hibernation with unsigned images, and some hardware diagnostic tools.

## Xwayland Input Isolation

**Set:** `XwaylandEavesdrops=None` in kwinrc

X11 applications cannot intercept input events from other windows. This blocks X11 keyloggers but also breaks global hotkeys, push-to-talk overlays (Discord, TeamSpeak), and some accessibility tools running under Xwayland. Native Wayland apps are unaffected.

## Other Disabled Services

| Service | Impact | Re-enable |
|---------|--------|-----------|
| `thermald` | Intel thermal management | `sudo systemctl enable --now thermald` |
| `alsa-state` | ALSA mixer volume persistence | `sudo systemctl enable --now alsa-state` |
| `sssd` | AD/LDAP/FreeIPA authentication | `sudo systemctl enable --now sssd` |
| `iscsid` | iSCSI storage targets | `sudo systemctl enable --now iscsid.socket` |
| `low-memory-monitor` | OOM warnings to desktop | `sudo systemctl enable --now low-memory-monitor` |

## Sysctl Restrictions (Non-Exhaustive)

| Setting | Impact |
|---------|--------|
| `kernel.dmesg_restrict=1` | Non-root users cannot read `dmesg` |
| `kernel.perf_event_paranoid=3` | `perf` profiling blocked for non-root |
| `kernel.io_uring_disabled=2` | io_uring disabled for unprivileged users |
| `kernel.core_pattern=\|/bin/false` | Core dumps discarded |
| `fs.binfmt_misc.status=0` | Cannot run foreign-arch binaries via QEMU user-mode |
| `vdso32=0`, `vsyscall=none` | Some legacy 32-bit binaries may break |

## Community Examples

These are images derived from this template (or similar enough to this template). Reference them when building your image!

- [m2Giles' OS](https://github.com/m2giles/m2os)
- [bOS](https://github.com/bsherman/bos)
- [Homer](https://github.com/bketelsen/homer/)
- [Amy OS](https://github.com/astrovm/amyos)
- [VeneOS](https://github.com/Venefilyn/veneos)
