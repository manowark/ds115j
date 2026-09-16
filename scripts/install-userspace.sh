#!/bin/sh
# Install DS115j daily-ready userspace (MCU, fan, SMART amber, poweroff module)
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

install -d /usr/local/sbin /etc/systemd/system /etc/modules-load.d \
    "/lib/modules/$KVER/extra"

install -m 0755 \
    "$ROOT/scripts/syno-mcu.sh" \
    "$ROOT/scripts/syno-mcu-boot.sh" \
    "$ROOT/scripts/syno-fan.sh" \
    "$ROOT/scripts/smart-amber-led.sh" \
    "$ROOT/scripts/deploy-boot.sh" \
    /usr/local/sbin/

# keep a copy next to historical /root/deploy-boot.sh path
install -m 0755 "$ROOT/scripts/deploy-boot.sh" /root/deploy-boot.sh

install -m 0644 \
    "$ROOT/scripts/syno-mcu-boot-begin.service" \
    "$ROOT/scripts/syno-mcu-boot.service" \
    "$ROOT/scripts/syno-fan.service" \
    "$ROOT/scripts/smart-amber-led.service" \
    "$ROOT/scripts/smart-amber-led.timer" \
    /etc/systemd/system/

if [ -f "$ROOT/config/smartd.conf" ]; then
    if [ -f /etc/smartd.conf ] && [ ! -f /etc/smartd.conf.bak.pre-kit ]; then
        cp -a /etc/smartd.conf /etc/smartd.conf.bak.pre-kit
    fi
    install -m 0644 "$ROOT/config/smartd.conf" /etc/smartd.conf
fi

if [ -f "$ROOT/config/interfaces" ]; then
    echo "NOTE: not overwriting /etc/network/interfaces (see config/interfaces)."
fi

install -m 0644 "$ROOT/config/qnap-poweroff-ds115j.conf" \
    /etc/modules-load.d/qnap-poweroff-ds115j.conf
install -m 0644 "$ROOT/config/ds115j-modules.conf" \
    /etc/modules-load.d/ds115j.conf

if [ -f "$ROOT/modules/qnap-poweroff-ds115j.ko" ]; then
    install -m 0644 "$ROOT/modules/qnap-poweroff-ds115j.ko" \
        "/lib/modules/$KVER/extra/qnap-poweroff-ds115j.ko"
    depmod "$KVER"
    modprobe qnap-poweroff-ds115j || echo "WARN: modprobe failed (vermagic vs $KVER?)" >&2
fi

if [ -f "$ROOT/config/zramswap" ] && [ -d /etc/default ]; then
    install -m 0644 "$ROOT/config/zramswap" /etc/default/zramswap
fi

if [ -f "$ROOT/config/journald.conf" ]; then
    install -d /etc/systemd/journald.conf.d
    install -m 0644 "$ROOT/config/journald.conf" /etc/systemd/journald.conf.d/ds115j.conf
fi

systemctl daemon-reload
systemctl enable --now syno-mcu-boot-begin.service syno-mcu-boot.service \
    syno-fan.service smart-amber-led.timer 2>/dev/null || true
systemctl enable smartd.service 2>/dev/null || true
systemctl restart smartd.service 2>/dev/null || true

# dbus was missing on an early tree; reboot/timedatectl need it
if [ -e /usr/lib/systemd/system/dbus.service ]; then
    ln -sfn /usr/lib/systemd/system/dbus.service \
        /etc/systemd/system/multi-user.target.wants/dbus.service
fi

echo "install-userspace: done"
echo "check: systemctl --failed; /usr/local/sbin/syno-mcu.sh ping; lsmod | grep qnap"
