#!/usr/bin/env bash
# Copy the built SD-card image out of the build volume into ./deploy/.
set -euo pipefail
cd "$(dirname "$0")/.."

IMAGE="${OMELET_BUILDER_IMAGE:-omelet-yocto-builder:latest}"
VOLUME="${OMELET_BUILD_VOLUME:-omelet-build}"
DEST="deploy"
mkdir -p "$DEST"

docker run --rm -v "$PWD/$DEST":/out -v "$VOLUME":/build \
    --entrypoint bash "$IMAGE" -c '
set -e
D=/build/build/tmp/deploy/images/raspberrypi4-64
if ! ls "$D"/*.wic.bz2 >/dev/null 2>&1; then
    echo "No .wic.bz2 found in $D - has the build finished?" >&2
    exit 1
fi
cp -v "$D"/*.wic.bz2 /out/
cp -v "$D"/*.wic.bmap /out/ 2>/dev/null || true
chmod 0644 /out/* 2>/dev/null || true
'
echo "Image(s) copied to ./$DEST:"
ls -lh "$DEST"
cat <<'EOF'

Flash to an SD card (macOS):
  diskutil list                       # find your card, e.g. /dev/disk4
  diskutil unmountDisk /dev/diskN
  bzcat deploy/omelet-image-*.wic.bz2 | sudo dd of=/dev/rdiskN bs=4m
  diskutil eject /dev/diskN
EOF
