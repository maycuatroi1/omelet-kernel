#!/usr/bin/env bash
# Boot the built Omelet Pi 4 image in QEMU (machine raspi4b) for a quick
# kernel + userspace smoke test.
#
#   ./scripts/run-qemu.sh           # extract kernel/dtb, prep SD, boot QEMU
#
# This is NOT a test of the Pi hardware features: under QEMU raspi4b there is
# no USB/PCIe, no on-board WiFi/BT, no VideoCore GPU and no genet Ethernet, so
# the pentest capabilities cannot be exercised here. It proves the -omelet
# kernel boots and userspace (systemd, login, binaries) comes up.
# See docs/07-run-in-qemu.md for the full story.
#
# Quit QEMU with:  Ctrl-A  then  X
set -euo pipefail
cd "$(dirname "$0")/.."

IMAGE="${OMELET_BUILDER_IMAGE:-omelet-yocto-builder:latest}"
VOLUME="${OMELET_BUILD_VOLUME:-omelet-build}"
WORK="${OMELET_QEMU_DIR:-qemu}"
# In QEMU the SD card enumerates as mmcblk1 (not mmcblk0 as on real HW), and the
# stdio PL011 UART registers as ttyAMA1 (not ttyAMA0). Override if yours differ.
ROOTDEV="${OMELET_QEMU_ROOT:-/dev/mmcblk1p2}"
CONSOLE="${OMELET_QEMU_CONSOLE:-ttyAMA1}"

command -v qemu-system-aarch64 >/dev/null \
    || { echo "qemu-system-aarch64 not found. Install it: brew install qemu (macOS) / apt install qemu-system-arm (Linux)"; exit 1; }
qemu-system-aarch64 -machine help 2>/dev/null | grep -q '^raspi4b' \
    || { echo "This QEMU has no 'raspi4b' machine (need QEMU >= 8.x)."; exit 1; }

mkdir -p "$WORK"

# 1. Pull the kernel Image + Pi 4 dtb out of the build volume (once).
if [ ! -f "$WORK/Image" ] || [ ! -f "$WORK/bcm2711-rpi-4-b.dtb" ]; then
    echo ">> Extracting Image + bcm2711-rpi-4-b.dtb from volume '$VOLUME' ..."
    docker run --rm -v "$PWD/$WORK":/out -v "$VOLUME":/build --entrypoint bash "$IMAGE" -c '
        set -e
        D=/build/build/tmp/deploy/images/raspberrypi4-64
        cp -fL "$D"/Image "$D"/bcm2711-rpi-4-b.dtb /out/'
fi

# 2. Decompress the newest deploy image and pad it to a power-of-2 size
#    (QEMU's SD controller refuses any other size).
WIC_BZ2=$(ls -t deploy/omelet-image-*.wic.bz2 2>/dev/null | head -1 || true)
[ -n "$WIC_BZ2" ] \
    || { echo "No deploy/*.wic.bz2 found. Run ./scripts/deploy-image.sh first."; exit 1; }

if [ ! -f "$WORK/sd.img" ] || [ "$WIC_BZ2" -nt "$WORK/sd.img" ]; then
    echo ">> Decompressing $WIC_BZ2 -> $WORK/sd.img ..."
    bunzip2 -kc "$WIC_BZ2" > "$WORK/sd.img"
    cur=$(wc -c < "$WORK/sd.img")
    size=1; while [ "$size" -lt "$cur" ]; do size=$((size * 2)); done   # next power of 2
    echo ">> Padding SD image to $size bytes ..."
    if command -v truncate >/dev/null; then
        truncate -s "$size" "$WORK/sd.img"
    else
        dd if=/dev/zero of="$WORK/sd.img" bs=1 count=0 seek="$size" 2>/dev/null
    fi
fi

# 3. Boot. boot.mount (/dev/mmcblk0p1 in fstab) and psplash's fb0 wait would each
#    stall ~90s under QEMU, so mask them for a fast, clean boot to a login prompt.
echo ">> Booting Omelet in QEMU raspi4b  (quit: Ctrl-A then X)"
exec qemu-system-aarch64 -M raspi4b -m 2G \
    -kernel "$WORK/Image" -dtb "$WORK/bcm2711-rpi-4-b.dtb" \
    -drive file="$WORK/sd.img",format=raw,if=sd \
    -append "rootwait root=$ROOTDEV console=$CONSOLE,115200 net.ifnames=0 \
             systemd.mask=boot.mount \
             systemd.mask=psplash-start.service systemd.mask=psplash-quit.service \
             systemd.mask=systemd-networkd-wait-online.service" \
    -nographic -no-reboot
