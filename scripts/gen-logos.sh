#!/usr/bin/env bash
# Regenerate the boot logo assets from assets/omelet-logo.png:
#   * kernel framebuffer logo  -> meta-omelet/recipes-kernel/linux/files/omelet-logo.ppm
#   * psplash userspace splash -> meta-omelet/recipes-core/psplash/files/psplash-poky-img.png
# Runs inside the builder image (imagemagick + netpbm), so results are reproducible.
set -euo pipefail
cd "$(dirname "$0")/.."

IMG="${OMELET_BUILDER_IMAGE:-omelet-yocto-builder:latest}"
SRC="assets/omelet-logo.png"
KERNEL_PPM="meta-omelet/recipes-kernel/linux/files/omelet-logo.ppm"
PSPLASH_PNG="meta-omelet/recipes-core/psplash/files/psplash-poky-img.png"

docker run --rm -v "$PWD":/work -w /work --entrypoint bash "$IMG" -c "
set -e
# Kernel logo: flatten alpha onto black, fit to 120px tall, quantize to <=224
# colors, emit ASCII (plain) PPM that the kernel logo tool accepts.
convert '$SRC' -background black -alpha remove -alpha off -resize x120 -depth 8 ppm:- \
  | pnmquant 224 \
  | pnmtoplainpnm > '$KERNEL_PPM'

# psplash splash: keep transparency so it blends over the splash background.
convert '$SRC' -resize 256x256 -strip -depth 8 '$PSPLASH_PNG'

echo '--- kernel logo ---'
head -2 '$KERNEL_PPM'
echo \"colors: \$(ppmhist '$KERNEL_PPM' | tail -n +1 | wc -l)\"
echo '--- psplash png ---'
identify '$PSPLASH_PNG'
"
echo "Logos regenerated:"
ls -l "$KERNEL_PPM" "$PSPLASH_PNG"
