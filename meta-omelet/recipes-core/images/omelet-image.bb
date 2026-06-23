SUMMARY = "Omelet - Raspberry Pi 4 image with the Omelet kernel + opencode AI agent"
LICENSE = "MIT"

inherit core-image

# Dev image: passwordless root + serial autologin. Remove "debug-tweaks"
# for a hardened build.
IMAGE_FEATURES += "ssh-server-openssh splash debug-tweaks"

# psplash splash is enabled via the "splash" IMAGE_FEATURE above.

IMAGE_INSTALL:append = " \
    omelet-base \
    opencode \
    ca-certificates \
    kernel-modules \
    git \
    curl \
    bash \
    nano \
    htop \
    tmux \
    rsync \
    iw \
    wpa-supplicant \
    iproute2 \
    openssh-sftp-server \
    omelet-wifi \
    networkmanager \
    networkmanager-nmcli \
    networkmanager-wifi \
    networkmanager-nmtui \
    "

# Give opencode + builds some breathing room.
IMAGE_ROOTFS_EXTRA_SPACE = "1048576"

# Produce a flashable SD-card image (.wic) plus bmap for fast flashing.
IMAGE_FSTYPES = "wic.bz2 wic.bmap"
