---
name: flash-pi-image-macos
description: Flash a built Raspberry Pi SD-card image to a card on macOS. Use when the user asks to "flash", "burn", "write image to SD", "ghi thẻ SD", "flash Pi", or to put the Yocto-built omelet-image (.wic.bz2) onto a microSD for a Raspberry Pi 4. Covers finding the SD device safely with diskutil, the dd streaming pipeline, and the Raspberry Pi Imager (rpi-imager) GUI/CLI tool already installed on this Mac.
---

# Flash a Pi image to SD card (macOS)

## Tooling on this Mac
- **Raspberry Pi Imager** — installed via Homebrew cask `raspberry-pi-imager`.
  - App: `/Applications/Raspberry Pi Imager.app`
  - Binary / CLI: `/Applications/Raspberry Pi Imager.app/Contents/MacOS/rpi-imager`
  - **Not on PATH** by default; call by full path or symlink it: `ln -s "/Applications/Raspberry Pi Imager.app/Contents/MacOS/rpi-imager" /opt/homebrew/bin/rpi-imager`
- **`dd` + `bzcat`** — built-in; the most reliable path for this project because the build output is `.wic.bz2`.

## What we flash
- Build artifacts live in `./deploy/` after `scripts/deploy-image.sh` runs.
- The image to flash is the newest `deploy/omelet-image-*.wic.bz2` (compressed Yocto `wic` SD image for `raspberrypi4-64`).
- If `deploy/` is empty, the build hasn't been copied out yet — run `./scripts/deploy-image.sh` (see [[yocto-build-macos-docker]]).

## Quickest: `make flask`
The repo Makefile wraps the script: `make disks` to find the card, then
`make flask DISK=/dev/disk4` (add `IMAGE=…` for a specific file, `YES=1` to skip the prompt,
or `SUDO_PASSWORD=… … YES=1` for non-interactive). `make flash` is an alias.

## Helper script (what `make flask` calls)
`scripts/flash.sh` wraps the whole flow with safety guards: refuses the internal system disk, requires an explicit `/dev/diskN`, confirms, then decompresses → unmounts → `dd` → ejects.

```bash
# 1. Find the card. NOTE: the built-in SDXC reader shows up as "internal, physical"
#    with `Device Location: Internal` — so `diskutil list external` may MISS it.
#    Use the full list and match by size / "Built In SDXC Reader" / Secure Digital.
diskutil list

# 2. Flash newest deploy/*.wic.bz2 to that card (e.g. disk4)
.claude/skills/flash-pi-image-macos/scripts/flash.sh /dev/disk4
# or an explicit image:
.claude/skills/flash-pi-image-macos/scripts/flash.sh /dev/disk4 deploy/omelet-image.wic.bz2
```

### Non-interactive (running from a tool / no TTY)
`bzcat IMAGE | sudo dd ...` FAILS without a TTY: `sudo: a terminal is required to read the password`.
The script handles this by decompressing to a temp file first (so `dd` reads from a file and
stdin is free to feed the password to `sudo -S`). Pass `-y` to skip the confirmation prompt and
export `SUDO_PASSWORD`:

```bash
SUDO_PASSWORD='…' .claude/skills/flash-pi-image-macos/scripts/flash.sh -y /dev/disk4
```
Never hard-code or persist the password. Provide it inline only for the single run.

## Manual: `dd` pipeline (what deploy-image.sh prints)
```bash
diskutil list                                   # find the card, e.g. /dev/disk4
diskutil unmountDisk /dev/diskN                 # unmount (do NOT eject yet)
bzcat deploy/omelet-image-*.wic.bz2 | sudo dd of=/dev/rdiskN bs=4m   # note: rdiskN (raw = fast)
diskutil eject /dev/diskN                       # safe to remove
```

## Manual: Raspberry Pi Imager GUI
1. Open `/Applications/Raspberry Pi Imager.app`.
2. **Choose OS → Use custom**.
3. rpi-imager reads `.img/.zip/.gz/.xz/.zst` but **not `.bz2`** — decompress first:
   `bunzip2 -k deploy/omelet-image-*.wic.bz2` → produces a `.wic`, select that file.
4. **Choose Storage** → the SD card → **Write**.

## Safety rules (must follow)
- **Always** identify the card with `diskutil list` first and confirm size matches the card. Picking the wrong disk destroys data.
- **Never** target `/dev/disk0` (internal system disk) or any internal/synthesized disk.
- Use the **raw** node `/dev/rdiskN` with `dd` (much faster than `/dev/diskN`).
- `unmountDisk` (whole disk) before flashing; `eject` after.
- macOS `dd` has no `status=progress`. The helper shows a **live progress line** by polling dd with SIGINFO (cumulative bytes) every ~3 s — `make flask` / `flash.sh` print `NNN / NNN MiB (NN%)` automatically. If you run `dd` by hand, press **Ctrl-T** for a one-off readout. Installing `pv` (`brew install pv`) gives a fancier bar in interactive runs.

## Gotchas
- macOS `dd` block-size flag is `bs=4m` (lowercase `m`), unlike Linux `bs=4M`.
- **Built-in SD reader is reported as `internal`.** Don't rely on `diskutil list external`; the guard in `flash.sh` only blocks `Location:Internal` **AND** `Removable:Not removable`, so it correctly permits the removable card while still refusing disk0.
- **`diskutil eject` powers the card down** in the built-in reader — the device node disappears and you must physically re-insert it before flashing again. Don't eject until you're truly done.
- `bzcat | sudo dd` needs a TTY for the sudo password — fails non-interactively (see Non-interactive section). The temp-file path avoids it.
- "Resource busy" → something re-mounted the card; run `diskutil unmountDisk` again (add `force` if needed).
- The compressed `.wic.bz2` decompresses to a full image (~2.1 GB here); ensure the card is ≥ that size and `${TMPDIR:-/tmp}` has room.
- After flashing, macOS may pop "disk not readable" for the Linux rootfs partition — that's normal; click **Eject**, not Initialize.

## Verified working (2026-06-23)
Flashed `omelet-image-raspberrypi4-64.rootfs.wic` (2.1 GB) to the Built In SDXC Reader at `/dev/disk4`
@ ~26 MB/s in 86 s. Resulting card: `boot` (FAT32, 136 MB) + `Linux` (2.1 GB) — correct Pi4 layout.
