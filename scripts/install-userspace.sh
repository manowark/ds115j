#!/bin/sh
# Install DS115j daily-ready userspace (network, data, apt, MCU, fan, SMART,
# zram, chrony, HDD idle standby, and poweroff module)
# onto the running NAS. Run as root from this repo's root:
#   sh scripts/install-userspace.sh
#
# Does not touch sda2, SPI, or U-Boot env.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
KVER=$(uname -r)

if [ "$(id -u)" -ne 0 ]; then
    echo "run as root" >&2
    exit 1
fi

backup_once() {
    file=$1
    if [ -e "$file" ] && [ ! -e "$file.bak.pre-ds115j-kit" ]; then
        cp -a "$file" "$file.bak.pre-ds115j-kit"
    fi
}

for required in \
    config/interfaces \
    config/10-ds115j-eth0.link \
    config/fstab \
    config/sources.list \
    config/zramswap \
    config/journald.conf \
    config/smartd.conf \
    config/smartmontools \
    config/disk-idle.service \
    scripts/disk-idle.service \
    scripts/install-disk-idle.sh \
    config/ds115j-modules.conf \
    config/qnap-poweroff-ds115j.conf \
    config/90-ds115j-tune.conf \
    config/usbcore-autosuspend-off.conf \
    config/90-ds115j-watchdog.conf \
    scripts/rtc-power-schedule.sh \
    modules/qnap-poweroff-ds115j.ko
do
    if [ ! -f "$ROOT/$required" ]; then
        echo "missing required kit file: $ROOT/$required" >&2
        exit 1
    fi
done

install -d /usr/local/sbin /etc/systemd/system /etc/systemd/network \
    /etc/systemd/journald.conf.d /etc/systemd/system.conf.d \
    /etc/modules-load.d /etc/modprobe.d /etc/sysctl.d \
    /etc/network /etc/default /srv/data "/lib/modules/$KVER/extra"

# Install boot-critical configuration before package setup. Do not restart
# networking here: doing so can drop the only SSH session. These settings are
# applied safely at the next reboot.
backup_once /etc/network/interfaces
backup_once /etc/systemd/network/10-ds115j-eth0.link
backup_once /etc/fstab
backup_once /etc/apt/sources.list
install -m 0644 "$ROOT/config/interfaces" /etc/network/interfaces
install -m 0644 "$ROOT/config/10-ds115j-eth0.link" \
    /etc/systemd/network/10-ds115j-eth0.link
install -m 0644 "$ROOT/config/fstab" /etc/fstab
install -m 0644 "$ROOT/config/sources.list" /etc/apt/sources.list

export DEBIAN_FRONTEND=noninteractive
dpkg --configure -a
apt-get update
apt-get install -y --no-install-recommends \
    ca-certificates \
    chrony \
    dbus \
    ifupdown \
    isc-dhcp-client \
    kmod \
    smartmontools \
    hdparm \
    zram-tools

install -m 0755 \
    "$ROOT/scripts/syno-mcu.sh" \
    "$ROOT/scripts/syno-mcu-boot.sh" \
    "$ROOT/scripts/syno-fan.sh" \
    "$ROOT/scripts/smart-amber-led.sh" \
    "$ROOT/scripts/deploy-boot.sh" \
    "$ROOT/scripts/syno-powerbtn.sh" \
    "$ROOT/scripts/syno-powerbtn-arm.sh" \
    /usr/local/sbin/

# keep a copy next to historical /root/deploy-boot.sh path
install -m 0755 "$ROOT/scripts/deploy-boot.sh" /root/deploy-boot.sh

install -m 0644 \
    "$ROOT/scripts/syno-mcu-boot-begin.service" \
    "$ROOT/scripts/syno-mcu-boot.service" \
    "$ROOT/scripts/syno-fan.service" \
    "$ROOT/scripts/smart-amber-led.service" \
    "$ROOT/scripts/smart-amber-led.timer" \
    "$ROOT/scripts/disk-idle.service" \
    "$ROOT/scripts/syno-powerbtn.service" \
    "$ROOT/scripts/syno-powerbtn-arm.service" \
    /etc/systemd/system/

backup_once /etc/smartd.conf
install -m 0644 "$ROOT/config/smartd.conf" /etc/smartd.conf

install -m 0644 "$ROOT/config/qnap-poweroff-ds115j.conf" \
    /etc/modules-load.d/qnap-poweroff-ds115j.conf
install -m 0644 "$ROOT/config/ds115j-modules.conf" \
    /etc/modules-load.d/ds115j.conf

# DSM parity tuning (docs/dsm-os-features.md): sysctl, USB autosuspend off,
# SoC watchdog feed. watchdog + usbcore take effect at next boot by design.
install -m 0644 "$ROOT/config/90-ds115j-tune.conf" \
    /etc/sysctl.d/90-ds115j-tune.conf
sysctl -q -p /etc/sysctl.d/90-ds115j-tune.conf || true
install -m 0644 "$ROOT/config/usbcore-autosuspend-off.conf" \
    /etc/modprobe.d/usbcore-autosuspend-off.conf
if [ -w /sys/module/usbcore/parameters/autosuspend ]; then
    echo -1 > /sys/module/usbcore/parameters/autosuspend 2>/dev/null || true
fi
install -m 0644 "$ROOT/config/90-ds115j-watchdog.conf" \
    /etc/systemd/system.conf.d/90-ds115j-watchdog.conf
install -m 0755 "$ROOT/scripts/rtc-power-schedule.sh" /usr/local/sbin/rtc-power-schedule.sh

install -m 0644 "$ROOT/modules/qnap-poweroff-ds115j.ko" \
    "/lib/modules/$KVER/extra/qnap-poweroff-ds115j.ko"
depmod "$KVER"
if ! modinfo qnap-poweroff-ds115j >/dev/null 2>&1; then
    echo "missing qnap-poweroff-ds115j module for $KVER" >&2
    exit 1
fi
modprobe qnap-poweroff-ds115j

install -m 0644 "$ROOT/config/zramswap" /etc/default/zramswap
install -m 0644 "$ROOT/config/journald.conf" \
    /etc/systemd/journald.conf.d/ds115j.conf

if ! mountpoint -q /srv/data; then
    mount /srv/data || true
fi
if ! mountpoint -q /srv/data; then
    echo "ERROR: /srv/data is not mounted; verify sda3 has LABEL=data." >&2
    exit 1
fi

systemctl daemon-reload
systemctl enable networking.service
systemctl enable --now chrony.service zramswap.service smartmontools.service
systemctl restart chrony.service zramswap.service smartmontools.service
systemctl enable --now syno-mcu-boot-begin.service syno-mcu-boot.service \
    syno-fan.service smart-amber-led.timer

# Power button: PIC arming (rc boot bytes) then the read-only poweroff listener.
# syno-powerbtn stays in OBSERVE mode unless /etc/syno-powerbtn.conf sets
# TRIGGER_BYTES (e.g. "30"). The arm unit writes only the two OEM LED-init bytes.
if [ -f "$ROOT/scripts/syno-powerbtn.conf" ]; then
    install -m 0644 "$ROOT/scripts/syno-powerbtn.conf" /etc/syno-powerbtn.conf
fi
systemctl enable --now syno-powerbtn-arm.service syno-powerbtn.service

# dbus.service is static on Debian, so wire it exactly as on the proven box.
if [ -e /usr/lib/systemd/system/dbus.service ]; then
    ln -sfn /usr/lib/systemd/system/dbus.service \
        /etc/systemd/system/multi-user.target.wants/dbus.service
fi
systemctl start dbus.service

# HDD 10-minute idle standby (hdparm, smartd -n standby,q, volatile journal,
# root noatime/commit=60). Does not restart networking or touch fan/MCU.
sh "$ROOT/scripts/install-disk-idle.sh"

echo "install-userspace: done"
echo "Network files are installed; reboot from UART to apply DHCP + eth0:1 safely."
echo "check after reboot: systemctl --failed; /usr/local/sbin/syno-mcu.sh ping; lsmod | grep qnap"
