# 07 - Testing the Omelet image in QEMU

> Boot the built **Omelet** Pi 4 image in QEMU for a fast kernel + userspace
> smoke test — no SD card or Raspberry Pi required.
>
> Authorized testing only.

This is the quickest way to confirm a build actually boots: the `-omelet`
kernel comes up, the ext4 rootfs mounts, systemd reaches multi-user, and you get
a login shell — all in software.

> ⚠️ **What QEMU does NOT test.** QEMU's `raspi4b` machine emulates the BCM2711
> only partially. It has **no USB / PCIe, no on-board WiFi/BT, no VideoCore GPU,
> and no genet Ethernet**. So none of the Omelet *implant* features (USB
> gadget/HID/BadUSB, WiFi injection, Bluetooth, the framebuffer logo, real
> networking) can be exercised here. QEMU verifies **the kernel boots and
> userspace works**; the hardware features need a **real Pi 4**.

---

## 0. Prerequisites

- A finished build — i.e. `deploy/omelet-image-*.wic.bz2` exists
  (run `./scripts/build.sh` then `./scripts/deploy-image.sh`; see
  [`06-install-yocto-macos.md`](06-install-yocto-macos.md) /
  [`05-install-yocto-wsl-linux.md`](05-install-yocto-wsl-linux.md)).
- **QEMU ≥ 8.x** with the `raspi4b` machine model.

Install QEMU and confirm the machine exists:

```bash
# macOS
brew install qemu
# Debian/Ubuntu/WSL
sudo apt install -y qemu-system-arm

qemu-system-aarch64 --version
qemu-system-aarch64 -machine help | grep raspi4b   # must print raspi4b
```

---

## 1. Quick start

```bash
./scripts/run-qemu.sh
```

That's it. The script (`scripts/run-qemu.sh`):

1. extracts the kernel `Image` + `bcm2711-rpi-4-b.dtb` from the build volume into
   `./qemu/`,
2. decompresses the newest `deploy/*.wic.bz2` to `./qemu/sd.img` and pads it to a
   power-of-2 size (QEMU's SD controller requires that),
3. boots `qemu-system-aarch64 -M raspi4b` with the correct console / root args.

**Quit QEMU:** press `Ctrl-A` then `X`.

Log in as `root` (passwordless, via the dev `debug-tweaks` feature). Then poke
around:

```bash
uname -r            # -> 6.6.63-omelet
cat /etc/motd
opencode --version
systemctl status
```

---

## 2. What a successful boot looks like

You should see, in order:

```
Booting Linux on physical CPU 0x0000000000
Linux version 6.6.63-omelet ...
...
EXT4-fs (mmcblk1p2): mounted filesystem ... 
Run /sbin/init as init process
Welcome to Omelet 1.0 (omelet)!
...
[  OK  ] Reached target Multi-User System.

Omelet 1.0 (omelet) raspberrypi4-64 ttyAMA1
raspberrypi4-64 login:
```

QEMU's `raspi4b` is slow (~10× wall-clock vs. guest time), so reaching the login
prompt can take 1–2 minutes. That's normal.

You will also see some units print **`FAILED`** along the way —
`systemd-resolved`, `systemd-timesyncd`, `systemd-logind`, `systemd-hostnamed`,
`dnsmasq`. These need a real network / RTC / DBus activation that the emulated
board doesn't provide; they do **not** stop the boot and the system still reaches
multi-user with a working console. Ignore them (see §4).

---

## 3. Doing it manually (and why each flag)

If you'd rather run QEMU by hand (or are on a native Linux build where the kernel
lives at `build/tmp/deploy/images/raspberrypi4-64/` instead of in a Docker
volume), here are the steps the script automates.

```bash
mkdir -p qemu && cd qemu

# 1. Get the kernel + Pi 4 dtb (from the macOS build volume) ...
docker run --rm -v "$PWD":/out -v omelet-build:/build --entrypoint bash \
  omelet-yocto-builder:latest -c '
    D=/build/build/tmp/deploy/images/raspberrypi4-64
    cp -fL "$D"/Image "$D"/bcm2711-rpi-4-b.dtb /out/'
# ... or on a native Linux build, just copy them from build/tmp/deploy/images/...

# 2. Decompress + pad the SD image to 4 GiB (next power of 2)
bunzip2 -kc ../deploy/omelet-image-*.wic.bz2 > sd.img
truncate -s 4G sd.img

# 3. Boot
qemu-system-aarch64 -M raspi4b -m 2G \
  -kernel Image -dtb bcm2711-rpi-4-b.dtb \
  -drive file=sd.img,format=raw,if=sd \
  -append "rootwait root=/dev/mmcblk1p2 console=ttyAMA1,115200 net.ifnames=0 \
           systemd.mask=boot.mount \
           systemd.mask=psplash-start.service systemd.mask=psplash-quit.service" \
  -nographic -no-reboot
```

The non-obvious bits — each was found by actually booting this image:

| Flag / step | Why it's needed |
|-------------|-----------------|
| pad `sd.img` to a power of 2 | QEMU's SD model rejects any other size (e.g. the raw 2.1 GB wic). |
| `-kernel Image -dtb …` | QEMU does **not** run the Pi's GPU firmware boot chain (`start4.elf`), so `config.txt`/`cmdline.txt` are ignored — you hand the kernel + dtb to QEMU directly. |
| `root=/dev/mmcblk1p2` | Under QEMU the SD card enumerates as **`mmcblk1`**, not `mmcblk0` as on real hardware. |
| `console=ttyAMA1,115200` | The stdio PL011 UART registers as **`ttyAMA1`** in QEMU. Using `ttyAMA0` gives *"unable to open an initial console"* and no login prompt. |
| `-nographic` (and **not** `-serial stdio`) | `-nographic` already wires the first serial to your terminal; adding `-serial stdio` too errors with *"cannot use stdio by multiple character devices"*. |
| `systemd.mask=boot.mount` | `/etc/fstab` mounts `/boot` from `mmcblk0p1`, which never appears under QEMU → a 90 s start-job stall. Masking it skips the wait. |
| `systemd.mask=psplash-*` | psplash waits on the framebuffer device `fb0`, which QEMU doesn't provide → another ~90 s stall. |
| `-m 2G` | `raspi4b` has a **fixed** 2 GB of RAM; other values are rejected. |

---

## 4. Limitations (don't chase these — they're expected)

These appear in the boot log and are **normal** for QEMU `raspi4b`:

- `bcm2711 dtc: ... pcie / genet-v5 / rng200 / thermal has been disabled!` —
  QEMU prunes unsupported peripherals. No PCIe ⇒ **no USB**; no genet ⇒ **no
  Ethernet on the Pi NIC** (NetworkManager still starts but has no usable link).
- `vchiq: vchiq_initialise: videocore not initialized` and the
  `bcm2835_audio/camera/codec/isp ... probe failed` lines — there is **no
  VideoCore GPU** in QEMU, so the multimedia/firmware drivers can't attach.
- `hci_uart_bcm: probe of serial0-0 failed` — **no on-board Bluetooth**.
- `Failed to start` for `systemd-resolved` / `systemd-timesyncd` /
  `systemd-logind` / `systemd-hostnamed` / `dnsmasq` — these depend on a real
  network, RTC, or DBus activation the emulated board lacks. Console login as
  `root` still works.

None of these block the boot.

---

## 5. Alternative: a `qemuarm64` image for clean userspace testing

If you only want to test **userspace** (the rootfs, `opencode`, your scripts) with
working **networking** and a fast, fully-supported QEMU machine, build a generic
`qemuarm64` image instead and use Yocto's own `runqemu`:

- It uses the generic ARMv8 `virt` machine with virtio drivers, so disk + network
  + console all "just work", and `runqemu` wires everything up.
- **Trade-off:** it's a *different kernel* (virt, not `linux-raspberrypi`), so it
  does **not** carry the Omelet Pi kernel config or board specifics — good for
  rootfs/app testing, useless for kernel/board testing.

That's a separate build target (add a kas entry with `MACHINE = "qemuarm64"`),
not covered here. For validating the actual Omelet kernel, use `raspi4b` above or
real hardware.

---

## 6. Troubleshooting

| Symptom | Fix |
|---------|-----|
| `qemu ... raspi4b ... is not a valid machine` | QEMU too old — upgrade to ≥ 8.x (`brew upgrade qemu`). |
| Boot hangs at *"Waiting for root device"* | Wrong `root=`. Watch the log for the `mmcblkN: pN pN` line and set `root=/dev/mmcblkNp2` (usually `mmcblk1p2`). |
| Kernel boots but no login prompt ever appears | Console mismatch — use `console=ttyAMA1,115200` (see §3). |
| `cannot use stdio by multiple character devices` | You passed both `-nographic` and `-serial stdio`; drop `-serial stdio`. |
| `Invalid SD card size` / SD errors | The image isn't a power-of-2 size — pad it (`truncate -s 4G sd.img`). |
| Stuck ~90 s on `mmcblk0p1` or `fb0` start jobs | Add the `systemd.mask=…` args from §3 (the script already does). |
| Can't exit QEMU | `Ctrl-A` then `X`. |

---

## 7. See also

- [`04-yocto-omelet.md`](04-yocto-omelet.md) — design of the kernel/image.
- [`05-install-yocto-wsl-linux.md`](05-install-yocto-wsl-linux.md) /
  [`06-install-yocto-macos.md`](06-install-yocto-macos.md) — how to produce the
  image this guide boots.
