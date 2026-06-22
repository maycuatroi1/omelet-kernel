# omelet-kernel

Custom **Omelet** Linux kernel + Yocto image for the **Raspberry Pi 4 (64-bit)**,
with the [**opencode**](https://opencode.ai) AI agent baked in by default and an
Omelet boot logo (kernel framebuffer + psplash splash).

> Kernel capabilities target authorized pentest/red-team use (owner-approved).
> Authorized testing only.

## What you get

- **Kernel:** `linux-raspberrypi` rebranded as **Omelet** (`uname -r` → `…-omelet`),
  with the Omelet config fragment (USB gadget/HID, mac80211 + injection-capable
  drivers, netfilter/tunnel, BT/BLE, I2C/SPI/CAN, storage forensics, overlayfs).
- **opencode** (`v1.17.9`, native aarch64 binary) on `PATH` out of the box.
- **Boot logo** from the Omelet logo, two ways:
  - kernel framebuffer logo (`CONFIG_LOGO`, shows the moment the kernel brings up
    the console), and
  - psplash userspace splash.
- **Distro:** poky + systemd, branded `Omelet`, with SSH, and dev-friendly
  defaults (`debug-tweaks`).

## Layout

| Path | What |
|------|------|
| `kas/omelet-pi4.yml` | kas build config: machine `raspberrypi4-64`, distro `omelet`, layers (poky + meta-openembedded + meta-raspberrypi) |
| `meta-omelet/` | the Omelet layer (kernel bbappend, opencode recipe, image, branding, splash) |
| `docker/` | local Yocto build-host image (Debian 12 + kas) — built from a cached base, no registry pull needed |
| `scripts/build.sh` | run a build/checkout/shell in the builder container |
| `scripts/gen-logos.sh` | regenerate the logo assets from `assets/omelet-logo.png` |
| `scripts/deploy-image.sh` | copy the finished `.wic.bz2` out of the build volume |
| `assets/omelet-logo.png` | source logo |
| `docs/04-yocto-omelet.md` | full design + build notes |

## Quick start (macOS / Apple Silicon)

Yocto can't build on macOS directly, and APFS is case-insensitive, so the build
runs inside a Linux container with the heavy build dir on a **case-sensitive
Docker volume**. `scripts/build.sh` wires all of that up.

```bash
# 1. Build the local Yocto build-host image (one time)
docker build -t omelet-yocto-builder docker/

# 2. Generate the boot logos from assets/omelet-logo.png (one time / on logo change)
./scripts/gen-logos.sh

# 3. Build the image (long: hours + tens of GB in the Docker volume)
./scripts/build.sh

# 4. Copy the SD-card image out and flash it
./scripts/deploy-image.sh
```

Output: `omelet-image-raspberrypi4-64.rootfs.wic.bz2` (a flashable SD image).

## Using opencode on the Pi

`opencode` is on `PATH`. Give it a provider key (it runs headless), then run it
in any project dir:

```bash
# put keys in /etc/omelet/api-keys and re-login, e.g.
echo 'export ANTHROPIC_API_KEY=sk-ant-...' >> /etc/omelet/api-keys
# or, interactively:
opencode auth login
opencode
```

Default model is set in `~/.config/opencode/opencode.json`.

See [docs/04-yocto-omelet.md](docs/04-yocto-omelet.md) for details.
