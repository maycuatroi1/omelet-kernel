# Ship the Omelet login banner as the system /etc/motd.
#
# WHY a base-files bbappend instead of a separate file in omelet-base:
#   base-files already owns /etc/motd (an empty placeholder). If a second
#   package (omelet-base) also installs /etc/motd, opkg refuses to overwrite a
#   file owned by another package, leaving omelet-base "half-installed" and
#   failing do_rootfs (opkg returns 255). Overriding the file from within the
#   recipe that owns it is the conflict-free, idiomatic fix.
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://motd"

do_install:append() {
    install -m 0644 ${WORKDIR}/motd ${D}${sysconfdir}/motd
}
