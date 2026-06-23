SUMMARY = "Omelet base branding + opencode runtime environment"
DESCRIPTION = "Installs the Omelet MOTD/banner, profile environment and a default \
opencode config so the AI agent is ready to use on first boot."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://omelet.sh \
    file://api-keys \
    file://opencode.json \
    file://vconsole.conf \
    file://locale.conf \
"

S = "${WORKDIR}"

# NOTE: the /etc/motd login banner is shipped by the base-files bbappend, not
# here. base-files already owns /etc/motd; installing it from a second package
# makes opkg refuse the overwrite, leaving this package half-installed and
# failing do_rootfs (opkg returns 255).

do_install() {
    # Shell environment (sources API keys, sets EDITOR, etc.)
    install -d ${D}${sysconfdir}/profile.d
    install -m 0644 ${S}/omelet.sh ${D}${sysconfdir}/profile.d/omelet.sh

    # Place to drop provider API keys (0600, not world readable)
    install -d ${D}${sysconfdir}/omelet
    install -m 0600 ${S}/api-keys ${D}${sysconfdir}/omelet/api-keys

    # Default opencode config for root.
    install -d ${D}/home/root/.config/opencode
    install -m 0644 ${S}/opencode.json ${D}/home/root/.config/opencode/opencode.json

    # Console + locale so the opencode TUI renders UTF-8 (block-art logo,
    # bullets) instead of mojibake. systemd-vconsole-setup reads vconsole.conf
    # to load a Unicode console font + put the VTs in UTF-8 mode; locale.conf
    # gives services/logins a UTF-8 default locale.
    install -d ${D}${sysconfdir}
    install -m 0644 ${S}/vconsole.conf ${D}${sysconfdir}/vconsole.conf
    install -m 0644 ${S}/locale.conf ${D}${sysconfdir}/locale.conf
}

FILES:${PN} = " \
    ${sysconfdir}/profile.d/omelet.sh \
    ${sysconfdir}/omelet/api-keys \
    ${sysconfdir}/vconsole.conf \
    ${sysconfdir}/locale.conf \
    /home/root/.config/opencode/opencode.json \
"

CONFFILES:${PN} = "${sysconfdir}/omelet/api-keys /home/root/.config/opencode/opencode.json"

# Branding pulls opencode in alongside it. kbd ships setfont + the
# Lat2-Terminus16 Unicode console font that vconsole.conf loads (without these
# systemd-vconsole-setup can't apply the font and the mojibake returns).
RDEPENDS:${PN} = "opencode kbd kbd-consolefonts"
