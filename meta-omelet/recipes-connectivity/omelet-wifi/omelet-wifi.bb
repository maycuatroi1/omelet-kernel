SUMMARY = "Friendly WiFi control CLI (omelet-wifi / wifi) wrapping nmcli"
DESCRIPTION = "A colourful nmcli wrapper so connecting the Pi 4 implant to WiFi \
is scan -> pick a number -> type the password. Installs the `omelet-wifi` tool \
plus a short `wifi` alias and a NetworkManager tuning drop-in."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://omelet-wifi \
    file://00-omelet.conf \
"

S = "${WORKDIR}"

do_install() {
    # The CLI, plus a short `wifi` alias pointing at it.
    install -d ${D}${bindir}
    install -m 0755 ${S}/omelet-wifi ${D}${bindir}/omelet-wifi
    ln -sf omelet-wifi ${D}${bindir}/wifi

    # NetworkManager tuning as a conf.d drop-in (no clash with the daemon's
    # own NetworkManager.conf).
    install -d ${D}${sysconfdir}/NetworkManager/conf.d
    install -m 0644 ${S}/00-omelet.conf ${D}${sysconfdir}/NetworkManager/conf.d/00-omelet.conf
}

FILES:${PN} = " \
    ${bindir}/omelet-wifi \
    ${bindir}/wifi \
    ${sysconfdir}/NetworkManager/conf.d/00-omelet.conf \
"

# bash for the script; NetworkManager + nmcli for the actual work; nmtui as the
# fallback full-screen interface the help text points at.
RDEPENDS:${PN} = " \
    bash \
    networkmanager \
    networkmanager-nmcli \
    networkmanager-wifi \
    networkmanager-nmtui \
"
