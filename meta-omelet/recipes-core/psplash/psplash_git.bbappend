# Omelet userspace boot splash.
# The psplash recipe converts SPLASH_IMAGES (psplash-poky-img.png) into the
# POKY_IMG header at build time. By prepending our files dir, the existing
# `psplash-poky-img.png` SRC_URI entry resolves to the Omelet image below.
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
