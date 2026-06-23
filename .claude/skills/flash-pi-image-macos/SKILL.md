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

## Recommended: helper script (safe)
`scripts/flash.sh` in this skill folder wraps the whole flow with safety guards (refuses the internal disk, requires an explicit external `/dev/diskN`, unmounts → streams → ejects).

```bash
# 1. See which disk the card is (external/physical only)
diskutil list external physical

# 2. Flash newest deploy/*.wic.bz2 to that card (e.g. disk4)
.claude/skills/flash-pi-image-macos/scripts/flash.sh /dev/disk4
# or pass an explicit image:
.claude/skills/flash-pi-image-macos/scripts/flash.sh /dev/disk4 deploy/omelet-image.wic.bz2
```

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
- `dd` is silent — press **Ctrl-T** to see progress, or add `status=progress` is not on macOS `dd`; the helper script prints byte counts via SIGINFO instead.

## Gotchas
- macOS `dd` block-size flag is `bs=4m` (lowercase `m`), unlike Linux `bs=4M`.
- "Resource busy" → something re-mounted the card; run `diskutil unmountDisk` again (add `force` if needed).
- The compressed `.wic.bz2` decompresses to a full-card-size raw image; ensure the card is ≥ the image's uncompressed size.
- After flashing, macOS may pop "disk not readable" for the Linux rootfs partition — that's normal; click **Eject**, not Initialize.
