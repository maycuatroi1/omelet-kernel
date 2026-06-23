# 05 - Installing Yocto (Windows WSL or Linux)

> A step-by-step guide for students to set up a working Yocto build host and
> build the **Omelet** Raspberry Pi 4 image from this repository.
>
> Authorized testing only.

This guide gets you from a bare Windows or Linux machine to a flashable SD-card
image. Unlike the macOS workflow in [`04-yocto-omelet.md`](04-yocto-omelet.md)
(which needs Docker + a case-sensitive volume to work around APFS), **Linux and
WSL2 already use a case-sensitive `ext4` filesystem**, so you can build Yocto
the normal way.

---

## 0. What you will build

| Item | Value |
|------|-------|
| Yocto release | **scarthgap (5.0 LTS)** |
| Target board | Raspberry Pi 4, 64-bit (`raspberrypi4-64`) |
| Build tool | [`kas`](https://kas.readthedocs.io) (drives BitBake from `kas/omelet-pi4.yml`) |
| Output | `omelet-image-raspberrypi4-64.rootfs.wic.bz2` (a flashable SD image) |

You do **not** need a Raspberry Pi to *build* the image — only to *run* it.

---

## 1. Hardware requirements

A Yocto build is heavy. Plan for:

| Resource | Minimum | Comfortable |
|----------|---------|-------------|
| Free disk | **50 GB** | 100 GB+ |
| RAM | 8 GB | 16 GB+ |
| CPU cores | 4 | 8+ |
| Time (first build) | a few hours | — |

> The first build downloads ~10 GB of source and compiles a full toolchain +
> kernel + rootfs. Later builds reuse the cache (`sstate`) and are much faster.

---

## 2. Pick your environment

You have two equally valid hosts:

- **Path A — Windows 10/11 with WSL2** → do **§3** then **§4**.
- **Path B — Native Linux** (Ubuntu 22.04 / 24.04 recommended) → skip to **§4**.

Either way, the actual build steps in **§5 onward are identical**.

---

## 3. Windows: set up WSL2 (Path A only)

WSL2 runs a real Linux kernel inside Windows. We use **Ubuntu 24.04 LTS**.

### 3.1 Install WSL2 + Ubuntu

Open **PowerShell as Administrator** and run:

```powershell
wsl --install -d Ubuntu-24.04
```

Reboot if asked. On first launch Ubuntu will prompt you to create a UNIX
username and password (this is *not* your Windows account — pick anything).

Verify you are on **version 2**:

```powershell
wsl -l -v
#   NAME            STATE           VERSION
# * Ubuntu-24.04    Running         2          <- must say 2
```

If it says `1`, convert it: `wsl --set-version Ubuntu-24.04 2`.

### 3.2 Give WSL enough RAM and CPU

Yocto can OOM-kill the compiler if RAM is too tight. Create the file
`C:\Users\<YourName>\.wslconfig` (in **Windows**, e.g. with Notepad):

```ini
[wsl2]
memory=12GB      # leave a few GB for Windows itself
processors=8
swap=8GB
```

Then apply it from PowerShell:

```powershell
wsl --shutdown
```

Re-open Ubuntu afterwards.

### 3.3 ⚠️ The single most important WSL rule

**Always build inside the Linux home directory (`~`), never under `/mnt/c/...`.**

The Windows drive is mounted at `/mnt/c`, but it is **case-insensitive and slow**.
Yocto requires a **case-sensitive** filesystem and will fail or crawl on
`/mnt/c`. Keep everything under `~` (which lives on a fast, case-sensitive
`ext4` virtual disk):

```bash
cd ~            # GOOD: ext4, case-sensitive, fast
# cd /mnt/c/... # BAD: NTFS, case-insensitive, slow — Yocto will break here
```

Now continue to **§4** inside the Ubuntu shell.

---

## 4. Prepare the Linux host (both paths)

These steps run inside your Linux/WSL shell.

### 4.1 Update and install Yocto's host packages

For **Ubuntu / Debian** (the scarthgap-required set):

```bash
sudo apt update && sudo apt full-upgrade -y

sudo apt install -y \
  gawk wget git diffstat unzip texinfo gcc build-essential \
  chrpath socat cpio python3 python3-pip python3-pexpect \
  xz-utils debianutils iputils-ping python3-git python3-jinja2 \
  python3-subunit zstd liblz4-tool file locales libacl1
```

<details>
<summary>Fedora / other distros</summary>

See the upstream list in the
[Yocto Quick Build](https://docs.yoctoproject.org/brief-yoctoprojectqs/index.html)
("Build Host Packages" section) and pick the block for your distro.
</details>

### 4.2 Set a UTF-8 locale (required)

BitBake refuses a non-UTF-8 locale.

```bash
sudo locale-gen en_US.UTF-8
sudo update-locale LANG=en_US.UTF-8
```

Log out and back in (or `exec bash`) so the new locale takes effect. Check:

```bash
locale | grep LANG     # should show en_US.UTF-8 (or C.UTF-8)
```

### 4.3 Do NOT build as root

BitBake refuses to run as `root`. Use your normal user (the one you created
during WSL setup, or your Linux login). If `whoami` prints `root`, create and
switch to a regular user first.

---

## 5. Get the source

Clone this repository into your Linux home directory:

```bash
cd ~
git clone <THIS-REPO-URL> omelet-kernel
cd omelet-kernel
```

> Replace `<THIS-REPO-URL>` with the URL your instructor gave you. If you copied
> the repo onto Windows, **do not** use it from `/mnt/c` — copy it into `~`
> first (`cp -r /mnt/c/path/to/omelet-kernel ~/` ) for the case-sensitivity
> reasons in §3.3.

The build config lives in `kas/omelet-pi4.yml` and the Omelet customisation in
`meta-omelet/`. You don't edit those to build — `kas` fetches poky and the other
layers for you.

---

## 6. Build the image

Pick **one** of the two methods below. **Method A (kas-container)** is the
easiest and most reproducible — start there.

### Method A — kas-container (Docker, recommended)

`kas-container` runs the whole build inside the official `kas` Docker image, so
you don't install any BitBake host packages yourself — only Docker.

**6A.1 Install Docker**

- *Native Linux:* install Docker Engine and add yourself to the `docker` group:
  ```bash
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER"
  newgrp docker          # or log out/in
  docker run --rm hello-world   # smoke test
  ```
- *Windows/WSL2:* install **Docker Desktop for Windows**, then in
  *Settings → Resources → WSL Integration* enable your Ubuntu distro. Confirm
  `docker run --rm hello-world` works inside the Ubuntu shell.

**6A.2 Get the `kas-container` helper**

```bash
cd ~/omelet-kernel
wget https://raw.githubusercontent.com/siemens/kas/master/kas-container
chmod +x kas-container
```

**6A.3 Build**

```bash
./kas-container build kas/omelet-pi4.yml
```

This clones the layers and runs the full build. Output lands in
`build/tmp/deploy/images/raspberrypi4-64/`.

### Method B — native kas (install kas on the host)

This runs BitBake directly on your machine. You learn more about the Yocto host
setup, but you must have installed the §4.1 packages.

**6B.1 Install kas**

Ubuntu 24.04 makes `pip` "externally managed", so use **pipx**:

```bash
sudo apt install -y pipx
pipx ensurepath
pipx install kas
exec bash            # reload PATH so `kas` is found
kas --version
```

**6B.2 Build**

```bash
cd ~/omelet-kernel
kas build kas/omelet-pi4.yml
```

> ℹ️ `scripts/build.sh` in this repo is **macOS-specific** (it wraps everything
> in a Docker volume to dodge APFS case-insensitivity). On Linux/WSL you don't
> need it — call `kas` directly as above.

### Build tuning (optional but useful)

`kas/omelet-pi4.yml` caps parallelism for an 8 GB machine:

```
BB_NUMBER_THREADS = "2"
PARALLEL_MAKE = "-j 4"
```

If your machine has **more RAM and cores**, raise these to build faster — e.g.
`BB_NUMBER_THREADS = "4"` and `PARALLEL_MAKE = "-j 8"`. They are in
`BB_BASEHASH_IGNORE_VARS`, so changing them does **not** trigger a full rebuild.

---

## 7. Get the image and flash an SD card

After a successful build the SD image is here:

```bash
ls -lh build/tmp/deploy/images/raspberrypi4-64/*.wic.bz2
```

> If you built with the repo's macOS Docker flow instead, use
> `./scripts/deploy-image.sh` to copy it into `./deploy/`. With Method A/B above
> the file is already on your filesystem at the path shown.

### Flashing

- **Easiest (Windows or Linux):** install
  [**Raspberry Pi Imager**](https://www.raspberrypi.com/software/) → *Choose OS*
  → *Use custom* → select the `.wic.bz2` → pick your SD card → *Write*.
  (On WSL: copy the file to Windows first, e.g.
  `cp build/tmp/.../*.wic.bz2 /mnt/c/Users/<You>/Desktop/`, then run Imager in
  Windows.) [balenaEtcher](https://etcher.balena.io/) works the same way.

- **Linux command line:**
  ```bash
  lsblk                                   # find your card, e.g. /dev/sdX
  sudo umount /dev/sdX*                    # unmount any auto-mounted partitions
  bzcat build/tmp/deploy/images/raspberrypi4-64/omelet-image-*.wic.bz2 \
    | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
  sync
  ```
  ⚠️ **Double-check `/dev/sdX`** — writing to the wrong device destroys data.
  USB-passthrough of an SD card into WSL2 is fiddly; flashing from Windows with
  Raspberry Pi Imager is the recommended route for WSL users.

### First boot

Insert the card, power the Pi 4, and either watch the serial console
(`ENABLE_UART=1`) or SSH in (`root`, passwordless via the dev `debug-tweaks`
feature — remove that for anything but a lab). `opencode` is on `PATH`.

---

## 8. Troubleshooting

| Symptom | Cause & fix |
|---------|-------------|
| `Please use a non-root user` / BitBake aborts immediately | You are `root`. Build as a normal user (§4.3). |
| `Please set a locale ... UTF-8` | Locale not UTF-8. Run §4.2, then re-login. |
| Build is extremely slow or fails with weird path/case errors (WSL) | You're building under `/mnt/c`. Move the repo to `~` (§3.3). |
| `fatal error: Killed signal terminated program cc1plus` | Out of memory. Lower `PARALLEL_MAKE`/`BB_NUMBER_THREADS`, or give WSL more RAM in `.wslconfig` (§3.2), then re-run — BitBake resumes from cache. |
| `No space left on device` / `Errno 28` | Disk full. Free up space (a build needs 50 GB+). On WSL the virtual disk also needs room on your Windows `C:` drive. |
| `git clone` of poky is painfully slow | This repo already points poky at the GitHub mirror in `kas/omelet-pi4.yml`; just retry — the first fetch is the slow one. |
| `docker: permission denied` (Method A) | Add yourself to the `docker` group and re-login: `sudo usermod -aG docker $USER` (§6A.1). |
| Clock-skew / certificate errors after the laptop slept (WSL) | WSL clock drifted. Fix with `sudo hwclock -s` or `wsl --shutdown` then reopen. |

### Resuming and cleaning

- Re-running `kas build kas/omelet-pi4.yml` **resumes** — finished tasks come
  from `sstate`, so an interrupted build does not start over.
- To rebuild a single recipe cleanly (Method B):
  `kas shell kas/omelet-pi4.yml -c "bitbake -c cleansstate <recipe>"`.
- **Never hard-kill a build mid-compile** (`docker stop`, killing the VM). Stop
  it with `Ctrl-C` (SIGINT) so in-flight compiles finish cleanly.

---

## 9. Where to go next

- [`04-yocto-omelet.md`](04-yocto-omelet.md) — full design of the Omelet kernel,
  image, boot logo, WiFi tooling, and the macOS build path.
- [Yocto Project Quick Build](https://docs.yoctoproject.org/brief-yoctoprojectqs/index.html)
  — upstream's own first-build walkthrough.
- [kas documentation](https://kas.readthedocs.io) — the build tool used here.
