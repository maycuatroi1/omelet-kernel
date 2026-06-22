#!/usr/bin/env bash
# Build the Omelet Pi 4 image inside the local Yocto builder container.
#
#   ./scripts/build.sh                 # full build of omelet-image
#   ./scripts/build.sh checkout        # just clone/checkout the layers
#   ./scripts/build.sh shell           # interactive bitbake shell
#   ./scripts/build.sh -- bitbake virtual/kernel -c menuconfig
#
# WHY a named Docker volume for the build dir:
#   macOS APFS is case-INSENSITIVE; Yocto requires a case-sensitive FS. Keeping
#   the heavy build output (tmp/sstate/downloads + cloned layers) inside the
#   ext4 Docker volume avoids that, and is far faster than a bind mount.
#   Only this repo (sources + meta-omelet) is bind-mounted at /work.
#
# Output image (inside the volume):
#   /build/build/tmp/deploy/images/raspberrypi4-64/omelet-image-raspberrypi4-64.rootfs.wic.bz2
# Copy it out with:  ./scripts/deploy-image.sh
set -euo pipefail
cd "$(dirname "$0")/.."

IMAGE="${OMELET_BUILDER_IMAGE:-omelet-yocto-builder:latest}"
VOLUME="${OMELET_BUILD_VOLUME:-omelet-build}"
KAS_FILE="kas/omelet-pi4.yml"

docker volume inspect "$VOLUME" >/dev/null 2>&1 || docker volume create "$VOLUME" >/dev/null

TTY_FLAGS="-i"
[ -t 1 ] && TTY_FLAGS="-it"

run() {
    docker run --rm $TTY_FLAGS \
        -v "$PWD":/work -w /work \
        -v "$VOLUME":/build \
        --security-opt seccomp=unconfined \
        "$IMAGE" "$@"
}

CMD="${1:-build}"
case "$CMD" in
  build|checkout|dump|lock)
    run kas "$CMD" "$KAS_FILE" ;;
  shell)
    run kas shell "$KAS_FILE" ;;
  --)
    shift; run "$@" ;;
  *)
    run kas "$@" "$KAS_FILE" ;;
esac
