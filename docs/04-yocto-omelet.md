# 04 - Omelet kernel + Yocto image for Pi 4

> Authorized testing only.

This replaces the earlier Buildroot plan (docs 01–03) with a **Yocto** build that
produces the **Omelet** kernel and a Pi 4 image with **opencode** baked in.

## Why Yocto here

- Layered + reproducible: the Omelet customization lives entirely in
  `meta-omelet/`, on top of upstream `meta-raspberrypi`.
- The Pi kernel recipe (`linux-raspberrypi`) inherits **kernel-yocto**, so the
  Omelet kernel config is a drop-in `.cfg` fragment merged over `bcm2711_defconfig`
  — no manual `.config` editing.
- First-class image features (splash, ssh, systemd) and a clean place to ship a
  prebuilt third-party binary (opencode).

## Build host: Docker on macOS

Yocto does not build on macOS, and APFS is **case-insensitive** (Yocto needs a
case-sensitive FS). So:

- `docker/Dockerfile` builds a Debian 12 + kas build host. It is built **from an
  already-cached base image** (`node:20-slim`), so it needs no registry pull —
  handy when Docker Desktop's credential helper can't reach a locked keychain.
- `scripts/build.sh` bind-mounts only this repo at `/work` and puts the heavy
  build output (`tmp/`, `sstate-cache/`, `downloads/`, and the cloned upstream
  layers) inside a **named Docker volume** (`omelet-build`, ext4 → case-sensitive).
- Target is `raspberrypi4-64` (aarch64). On Apple Silicon the host is also
  aarch64, so target compilation is native (no QEMU emulation of the toolchain).

```bash
docker build -t omelet-yocto-builder docker/   # one time
./scripts/build.sh checkout                     # clone + validate layers
./scripts/build.sh                              # full build
./scripts/deploy-image.sh                       # copy out the .wic.bz2
```

Heads-up: a cold build is hours long and the volume grows to tens of GB. Make
sure Docker Desktop has enough disk + memory (≥8 GB RAM, ≥80 GB disk recommended).

## meta-omelet contents

```
meta-omelet/
├── conf/
│   ├── layer.conf                 # layer metadata (compat: scarthgap)
│   └── distro/omelet.conf         # poky + systemd, branded "Omelet"
├── recipes-kernel/linux/
│   ├── linux-raspberrypi_%.bbappend   # merge omelet.cfg + install boot logo
│   └── files/
│       ├── omelet.cfg             # kernel config fragment (branding+logo+caps)
│       └── omelet-logo.ppm        # clut224 framebuffer logo (<=224 colors)
├── recipes-core/
│   ├── images/omelet-image.bb     # the image: opencode + tooling + splash
│   ├── omelet-base/...            # MOTD/banner, profile env, opencode config
│   └── psplash/
│       ├── psplash_git.bbappend   # override the splash image
│       └── files/psplash-poky-img.png
└── recipes-devtools/opencode/
    └── opencode_1.17.9.bb         # prebuilt aarch64 opencode binary
```

### Kernel (Omelet)

`linux-raspberrypi_%.bbappend`:
- Adds `omelet.cfg` to `SRC_URI`; kernel-yocto merges it onto `bcm2711_defconfig`.
- `CONFIG_LOCALVERSION="-omelet"` → `uname -r` shows `…-omelet`.
- `do_configure:prepend` overwrites `drivers/video/logo/logo_linux_clut224.ppm`
  with the Omelet logo, so the kernel's logo tool compiles it in.
- The fragment carries the pentest capabilities from the original design (USB
  gadget/HID, mac80211 + rtl8xxxu/ath9k_htc/etc, netfilter/WireGuard/TUN,
  BT/BLE, I2C/SPI/CAN, USB-serial bridges, NTFS3/exFAT, overlayfs).

### opencode

`opencode_1.17.9.bb` ships the upstream prebuilt aarch64 (glibc) binary:
- `SRC_URI` = the GitHub release tarball, pinned by `sha256sum`.
- It is a Bun-compiled self-contained binary → `INHIBIT_PACKAGE_STRIP` (stripping
  can corrupt the embedded payload) and `INSANE_SKIP` for the QA checks that don't
  apply to a third-party prebuilt.
- `omelet-base` provides a default `~/.config/opencode/opencode.json`, an
  `/etc/omelet/api-keys` drop-in (sourced on login) and a branded MOTD.

To update opencode: bump `PV`, drop the new `sha256sum` (the recipe filename
encodes the version), rebuild.

### Boot logo (both)

- **Kernel framebuffer logo** — `CONFIG_LOGO` + `CONFIG_LOGO_LINUX_CLUT224`, with
  the in-tree Tux replaced by `omelet-logo.ppm`. Shows the instant fbcon comes up.
- **psplash splash** — the psplash recipe converts `psplash-poky-img.png`
  (our Omelet image) into its `POKY_IMG` header at build time; we override that
  PNG via `FILESEXTRAPATHS`. Enabled by the image's `splash` feature.

Regenerate both from `assets/omelet-logo.png` with `scripts/gen-logos.sh`
(flatten+quantize for the kernel ppm; resize-keeping-alpha for psplash).

## Flashing

```bash
diskutil list
diskutil unmountDisk /dev/diskN
bzcat deploy/omelet-image-*.wic.bz2 | sudo dd of=/dev/rdiskN bs=4m
diskutil eject /dev/diskN
```

First boot: serial console on the UART (`ENABLE_UART=1`) or SSH in (root,
passwordless via `debug-tweaks` — remove that feature for anything but dev).
