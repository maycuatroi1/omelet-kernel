# Omelet kernel: brand the Pi 4 kernel + merge the Omelet config fragment and
# install the custom framebuffer boot logo.
#
# linux-raspberrypi inherits kernel-yocto, so a loose .cfg in SRC_URI is
# automatically merged on top of bcm2711_defconfig.
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += " \
    file://omelet.cfg \
    file://omelet-logo.ppm \
"

# Replace the in-tree Tux logo with the Omelet logo (clut224, <=224 colors)
# before the kernel's logo tool turns it into C at compile time.
do_configure:prepend() {
    if [ -f "${WORKDIR}/omelet-logo.ppm" ]; then
        install -m 0644 "${WORKDIR}/omelet-logo.ppm" \
            "${S}/drivers/video/logo/logo_linux_clut224.ppm"
    fi
}
