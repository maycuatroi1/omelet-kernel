# 06 - Installing Yocto on macOS (Apple Silicon)

> How to build the **Omelet** Raspberry Pi 4 image on a Mac, using the Docker
> workflow this repository already ships.
>
> Authorized testing only.

Yocto **cannot build natively on macOS**, for two reasons this guide works
around:

1. **APFS is case-insensitive.** Yocto requires a *case-sensitive* filesystem.
2. **macOS isn't a supported BitBake host** (the toolchain expects Linux).

So on a Mac we build inside a small Linux container, and keep the heavy build
output on a **case-sensitive `ext4` Docker volume**. Everything is wired up by
the scripts in `scripts/` — you mostly run three commands.

> If you are on **Windows or Linux**, use
> [`05-install-yocto-wsl-linux.md`](05-install-yocto-wsl-linux.md) instead — there
> you build the normal way and don't need any of this.

---

## 0. What you will build

| Item | Value |
|------|-------|
| Yocto release | **scarthgap (5.0 LTS)** |
| Target board | Raspberry Pi 4, 64-bit (`raspberrypi4-64`) |
| Build host | Debian 12 + `kas` 4.6 in a local Docker image (`omelet-yocto-builder`) |
| Build dir | a named Docker volume `omelet-build` (ext4, case-sensitive) |
| Output | `omelet-image-raspberrypi4-64.rootfs.wic.bz2` |

On **Apple Silicon** the container is `aarch64` and so is the Pi target →
**native compilation, no QEMU emulation** of the toolchain.

---

## 1. Hardware & disk — read this first

> 💥 **Disk headroom is the #1 way this build fails on a Mac.** A full build
> needs ~50 GB, written into Docker's virtual disk
> (`~/Library/Containers/com.docker.docker/Data/vms/.../Docker.raw`). If the Mac
> host disk hits 100% mid-build, writes fail with `Errno 5 I/O error` and that
> can **corrupt Docker's internal metadata** — after which `docker run` fails
> and only a **Docker Desktop restart** clears it.

| Resource | Recommended |
|----------|-------------|
| Free space on the Mac | **≥ 60 GB free** before you start |
| RAM given to Docker | ≥ 8 GB |
| Disk given to Docker's VM | ≥ 80 GB |
| First build time | a few hours |

Before building, check free space and keep an eye on it during long builds:

```bash
df -h /System/Volumes/Data
```

> ⚠️ The kas config sets `BB_DISKMON_DIRS`, but that watches the **VM's** virtual
> disk, **not** your Mac's real disk — it will *not* save you from the host disk
> filling up. Monitor `df -h` yourself.

If you're short on space, common reclaim sources on a Mac: `~/Library/Caches`,
Xcode's `~/Library/Developer/Xcode/iOS DeviceSupport`, and any old VM images
(`~/Parallels/*.pvm`).

---

## 2. Prerequisites

### 2.1 Docker Desktop

Install **Docker Desktop for Mac** (Apple Silicon build) and launch it once so
the engine is running. Then raise its limits in
**Settings → Resources**:

- **Memory:** ≥ 8 GB
- **Disk image size:** ≥ 80 GB

Confirm the CLI works:

```bash
docker version
docker run --rm hello-world     # should print "Hello from Docker!"
```

### 2.2 Command line tools + git

```bash
xcode-select --install      # if not already installed
git --version
```

Clone the repo somewhere under your home directory:

```bash
cd ~/git    # or wherever you keep projects
git clone <THIS-REPO-URL> omelet-kernel
cd omelet-kernel
```

---

## 3. About the Docker credential quirk (why the base is `node:20-slim`)

`docker/Dockerfile` builds the Yocto host **`FROM node:20-slim`** — a base that
is very likely **already cached** on a developer Mac. This is deliberate:

> On some macOS setups Docker Desktop's credential helper (`credsStore:
> desktop`) needs the **login keychain**, which is *locked* in non-interactive /
> headless sessions — so `docker pull` fails with *"keychain cannot be
> accessed."* Building from an already-cached base sidesteps the pull entirely.

**Implication:** if Docker needs to pull a base layer it doesn't have, and your
keychain is locked, the `docker build` will fail. Fix by **unlocking the
keychain interactively** (just log into the Mac GUI / open Keychain Access once),
or pre-pull the base in an interactive terminal, then re-run the build.

---

## 4. One-time setup

### 4.1 Build the Yocto build-host image

```bash
docker build -t omelet-yocto-builder docker/
```

This produces `omelet-yocto-builder:latest`: Debian 12 with all Yocto host
packages, `kas==4.6`, a UTF-8 locale, the image-conversion tools
(imagemagick/netpbm), and a non-root `builder` user (BitBake refuses to run as
root — the `entrypoint.sh` drops privileges with `gosu`).

### 4.2 Generate the boot logos

```bash
./scripts/gen-logos.sh
```

Regenerates the kernel framebuffer logo (`omelet-logo.ppm`) and the psplash
splash PNG from `assets/omelet-logo.png`, inside the builder image so the result
is reproducible. You only need to re-run this when the source logo changes.

---

## 5. Build the image

```bash
./scripts/build.sh            # full build of omelet-image (long!)
```

What `scripts/build.sh` does for you:

- bind-mounts **only this repo** at `/work` (your `meta-omelet`, kas config),
- mounts the named volume **`omelet-build`** at `/build` — the ext4,
  case-sensitive home for `tmp/`, `sstate-cache/`, `downloads/`, and the cloned
  upstream layers,
- runs `kas build kas/omelet-pi4.yml` as the `builder` user.

Other handy sub-commands:

```bash
./scripts/build.sh checkout   # just clone/checkout the layers, no build
./scripts/build.sh shell      # interactive BitBake shell in the container
./scripts/build.sh -- bitbake virtual/kernel -c menuconfig
```

> The build is **resumable**: finished tasks come from `sstate`, so re-running
> after an interruption does *not* start over.

### Build tuning

`kas/omelet-pi4.yml` caps parallelism for an ~8 GB Docker VM:

```
BB_NUMBER_THREADS = "2"
PARALLEL_MAKE = "-j 4"
```

If you gave Docker more RAM, you can raise these to build faster (e.g. `"4"` and
`"-j 8"`). They are in `BB_BASEHASH_IGNORE_VARS`, so changing them does **not**
invalidate the cache.

---

## 6. Get the image and flash an SD card

Copy the finished image out of the Docker volume:

```bash
./scripts/deploy-image.sh
```

It lands in `./deploy/` (`omelet-image-*.wic.bz2`, plus a `.wic.bmap` if present).

Flash it to an SD card (the script prints these too):

```bash
diskutil list                                   # find your card, e.g. /dev/disk4
diskutil unmountDisk /dev/diskN
bzcat deploy/omelet-image-*.wic.bz2 | sudo dd of=/dev/rdiskN bs=4m
diskutil eject /dev/diskN
```

> ⚠️ **Double-check `diskN`** — writing to the wrong disk destroys data. Use the
> **`/dev/rdiskN`** (raw) node for `dd`; it's much faster than `/dev/diskN`.

### First boot

Power the Pi 4 with the card. Watch the serial console (`ENABLE_UART=1`) or SSH
in (`root`, passwordless via the dev `debug-tweaks` feature — remove it for
anything but a lab). `opencode` is on `PATH`.

---

## 7. Troubleshooting (macOS-specific, hard-won)

| Symptom | Cause & fix |
|---------|-------------|
| `docker build` fails with *"keychain cannot be accessed"* | Locked keychain blocks the registry pull (§3). Unlock the Mac keychain interactively / pre-pull the base, then rebuild. |
| Build dies with `Errno 5 I/O error`, then `docker run` keeps failing (lease / overlay2 errors) | The **Mac host disk filled up** and corrupted Docker's metadata. Free space, then **restart Docker Desktop** to clear it. Keep ≥60 GB free (§1). |
| `No space left on device` inside the build | Docker's virtual disk is full — raise *Disk image size* in Docker settings, or free space and re-run. |
| `fatal error: Killed signal terminated program cc1plus` (often gcc/binutils near ~90%) | **OOM**, not corruption — too many recipes compiling at once for the RAM. It's transient: just re-run `./scripts/build.sh` (BitBake retries the 2 failed tasks from cache). The kas config already caps `BB_NUMBER_THREADS=2` / `PARALLEL_MAKE=-j4` for this reason. |
| Kernel `do_fetch` of `github.com/raspberrypi/linux` times out (exit 128) | That repo is a ~5.5 GB mirror; a flaky link kills the single clone. Re-run — BitBake resumes the fetch. (If it keeps failing, pre-clone it into the volume's `downloads/git2/...`, **owned by `builder`**, then re-run.) |
| poky clone is painfully slow | Already mitigated — `kas/omelet-pi4.yml` points poky at the GitHub mirror. Just retry; the first fetch is the slow one. |
| `do_rootfs` fails with opkg exit 255 and no inline error | Two recipes shipping the **same file** (e.g. `/etc/motd`) → opkg conflict. Read the leftover `…/rootfs/var/lib/opkg/status` for a package whose `Status:` is `half-installed` to find the culprit. |

### ❗ Never hard-kill a build

Do **not** `docker stop` a build mid-`do_compile` — it corrupts long in-flight
compiles (e.g. `gcc-cross` linking with `undefined reference to ...`). Stop it
**gracefully with `Ctrl-C` (SIGINT)** instead. If a compile did get corrupted:

```bash
./scripts/build.sh -- bitbake -c cleansstate gcc-cross-aarch64
./scripts/build.sh
```

---

## 8. Daily workflow cheat-sheet

```bash
docker build -t omelet-yocto-builder docker/   # one time (or on Dockerfile change)
./scripts/gen-logos.sh                          # one time (or on logo change)
./scripts/build.sh                              # build (resumable)
./scripts/deploy-image.sh                       # copy image into ./deploy/
# then flash with diskutil + dd (see §6)
```

---

## 9. See also

- [`04-yocto-omelet.md`](04-yocto-omelet.md) — full design of the Omelet kernel,
  image, boot logo, and WiFi tooling.
- [`05-install-yocto-wsl-linux.md`](05-install-yocto-wsl-linux.md) — the
  Windows/Linux build path (no Docker volume trickery needed there).
- [kas documentation](https://kas.readthedocs.io) — the build tool used here.
