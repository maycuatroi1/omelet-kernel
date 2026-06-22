SUMMARY = "opencode - AI coding agent for the terminal (prebuilt binary)"
DESCRIPTION = "opencode is an open-source AI coding agent built for the terminal. \
This recipe ships the upstream prebuilt aarch64 (glibc) release binary."
HOMEPAGE = "https://opencode.ai"
BUGTRACKER = "https://github.com/anomalyco/opencode/issues"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# opencode publishes per-arch tarballs that each contain a single `opencode` binary.
OPENCODE_ARCH:aarch64 = "arm64"
OPENCODE_ARCH:x86-64  = "x64"
OPENCODE_ARCH ?= "unsupported"

SRC_URI = "https://github.com/anomalyco/opencode/releases/download/v${PV}/opencode-linux-${OPENCODE_ARCH}.tar.gz;downloadfilename=opencode-${PV}-linux-${OPENCODE_ARCH}.tar.gz"

# sha256 for opencode-linux-arm64.tar.gz @ v1.17.9
SRC_URI[sha256sum] = "8cc511f9794e575e5d3c4c2654930d05670186df649c26b50889ac73c65dde21"

S = "${WORKDIR}"

# Prebuilt glibc binary: only aarch64 (Pi 4) and x86-64 hosts are supported.
COMPATIBLE_HOST = "(aarch64|x86_64).*-linux"

# It is a Bun-compiled self-contained binary with a trailing data section;
# do NOT strip it (strip can corrupt the embedded payload) and skip the QA
# checks that do not apply to a third-party prebuilt executable.
INHIBIT_PACKAGE_STRIP = "1"
INHIBIT_SYSROOT_STRIP = "1"
INHIBIT_PACKAGE_DEBUG_SPLIT = "1"
INSANE_SKIP:${PN} += "already-stripped ldflags textrel"

RDEPENDS:${PN} += "glibc libstdc++ libgcc"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${S}/opencode ${D}${bindir}/opencode
}

FILES:${PN} = "${bindir}/opencode"
