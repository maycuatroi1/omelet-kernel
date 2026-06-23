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
    file://timesyncd-ntp.conf \
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

    # NTP time sync so HTTPS certs validate on the RTC-less Pi4 (otherwise the
    # stale boot clock trips "certificate is not yet valid" -- see the drop-in).
    install -d ${D}${sysconfdir}/systemd/timesyncd.conf.d
    install -m 0644 ${S}/timesyncd-ntp.conf \
        ${D}${sysconfdir}/systemd/timesyncd.conf.d/omelet-ntp.conf

    # Enable systemd-timesyncd.service explicitly. It is part of the systemd
    # package (timesyncd is in its default PACKAGECONFIG), but we ship the
    # enable symlink ourselves instead of relying on the distro preset, so the
    # service is guaranteed active regardless of preset policy. The unit's
    # [Install] section is WantedBy=sysinit.target. Path is the usrmerge
    # location (DISTRO_FEATURES has usrmerge), so /lib -> /usr/lib.
    install -d ${D}${sysconfdir}/systemd/system/sysinit.target.wants
    ln -sf /usr/lib/systemd/system/systemd-timesyncd.service \
        ${D}${sysconfdir}/systemd/system/sysinit.target.wants/systemd-timesyncd.service
}

FILES:${PN} = " \
    ${sysconfdir}/profile.d/omelet.sh \
    ${sysconfdir}/omelet/api-keys \
    ${sysconfdir}/vconsole.conf \
    ${sysconfdir}/locale.conf \
    ${sysconfdir}/systemd/timesyncd.conf.d/omelet-ntp.conf \
    ${sysconfdir}/systemd/system/sysinit.target.wants/systemd-timesyncd.service \
    /home/root/.config/opencode/opencode.json \
"

CONFFILES:${PN} = "${sysconfdir}/omelet/api-keys /home/root/.config/opencode/opencode.json ${sysconfdir}/systemd/timesyncd.conf.d/omelet-ntp.conf"

# Branding pulls opencode in alongside it. kbd ships setfont + the
# Lat2-Terminus16 Unicode console font that vconsole.conf loads (without these
# systemd-vconsole-setup can't apply the font and the mojibake returns).
# systemd provides systemd-timesyncd.service, which our enable symlink targets.
RDEPENDS:${PN} = "opencode kbd kbd-consolefonts systemd"
