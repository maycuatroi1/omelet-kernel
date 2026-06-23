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
├── recipes-connectivity/
│   ├── networkmanager/networkmanager_%.bbappend  # enable nmtui
│   └── omelet-wifi/              # `wifi` CLI + NetworkManager tuning drop-in
│       ├── omelet-wifi.bb
│       └── files/{omelet-wifi,00-omelet.conf}
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

### Console UTF-8

The opencode TUI draws its logo from Unicode block elements (`█ ▀ ▄`, U+2580–259F)
and uses `•` bullets. On a stock console these came out as mojibake (`âûê…`) —
the multi-byte UTF-8 was being decoded one byte at a time through the 8-bit
CP437 kernel font. Three layers fix it, all in `meta-omelet`:

- **VT in UTF-8 mode** — `CMDLINE:append = " vt.default_utf8=1"` (kas
  `raspberrypi` header) forces UTF-8 from the first boot message.
- **Unicode console font** — `omelet-base` ships `/etc/vconsole.conf`
  (`FONT=Lat2-Terminus16`) and pulls in `kbd` + `kbd-consolefonts`;
  `systemd-vconsole-setup` loads the font and sets the VTs to UTF-8 at boot.
- **Default locale** — `/etc/locale.conf` (`LANG=C.UTF-8`, built into glibc, no
  generation) plus a `LANG` export in `omelet.sh` so the login shell that
  launches opencode agrees on UTF-8.

### WiFi (NetworkManager + `wifi` CLI)

Networking is handled by **NetworkManager** (from `meta-networking`). The repo
ships no static network config, so NM is the sole manager — it auto-DHCPs both
`eth0` and `wlan0` and reconnects saved networks on boot. WiFi support pulls in
`wpa-supplicant` (NM drives it over D-Bus); the `networkmanager_%.bbappend`
turns on the `nmtui` PACKAGECONFIG so the ncurses UI is available too.

`omelet-wifi` (recipe `recipes-connectivity/omelet-wifi`) is a friendly bash
wrapper around `nmcli`, installed as `omelet-wifi` and the short alias `wifi`:

```
wifi                      # interactive menu (status + actions)
wifi connect [SSID]       # scan, pick a number, type the password
wifi scan | status | list | forget <SSID> | disconnect | on | off
```

Connecting saves a NetworkManager profile (autoconnect on), so the implant
re-joins the network automatically after a reboot. `00-omelet.conf` is a
`conf.d` drop-in that disables WiFi power-save (stable link) and scan MAC
randomisation (predictable for MAC allow-lists — remove it for stealth).
The regulatory database is already in the image via `packagegroup-base-wifi`
(`wireless-regdb-static`) — don't also add `wireless-regdb`, the two conflict.

## Flashing

```bash
diskutil list
diskutil unmountDisk /dev/diskN
bzcat deploy/omelet-image-*.wic.bz2 | sudo dd of=/dev/rdiskN bs=4m
diskutil eject /dev/diskN
```

First boot: serial console on the UART (`ENABLE_UART=1`) or SSH in (root,
passwordless via `debug-tweaks` — remove that feature for anything but dev).
