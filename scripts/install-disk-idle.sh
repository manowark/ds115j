#!/bin/sh
# HDD idle standby (10 minutes) for a running DS115j.
# Safe to re-run. Does not touch SPI, U-Boot env, fan, MCU, or networking.
#
#   sh scripts/install-disk-idle.sh
#
# Called from install-userspace.sh as well.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

if [ "$(id -u)" -ne 0 ]; then
    echo "run as root" >&2
    exit 1
fi

backup_once() {
    file=$1
    stamp=$2
    if [ -e "$file" ] && [ ! -e "$file.$stamp" ]; then
        cp -a "$file" "$file.$stamp"
    fi
}

for required in \
    scripts/disk-idle.service \
    config/smartd.conf \
    config/journald.conf \
    config/smartmontools
do
    if [ ! -f "$ROOT/$required" ]; then
        echo "missing required kit file: $ROOT/$required" >&2
        exit 1
    fi
done

export DEBIAN_FRONTEND=noninteractive
dpkg --configure -a || true
apt-get update
apt-get install -y --no-install-recommends hdparm

HDPARM=$(command -v hdparm || true)
if [ -z "$HDPARM" ]; then
    echo "hdparm missing after apt install" >&2
    exit 1
fi
if [ ! -x /usr/sbin/hdparm ]; then
    echo "expected /usr/sbin/hdparm (systemd unit path)" >&2
    exit 1
fi

# --- smartd: -n standby,q and keep -M exec amber hook ---
backup_once /etc/smartd.conf bak.pre-disk-idle
install -m 0644 "$ROOT/config/smartd.conf" /etc/smartd.conf
if ! grep -q -- '-n standby,q' /etc/smartd.conf; then
    echo "smartd.conf missing -n standby,q" >&2
    exit 1
fi
if ! grep -q -- '-M exec /usr/local/sbin/smart-amber-led.sh' /etc/smartd.conf; then
    echo "smartd.conf missing SMART amber -M exec" >&2
    exit 1
fi

# --- smartd poll interval >= 3600s ---
backup_once /etc/default/smartmontools bak.pre-disk-idle
if [ -e /etc/default/smartmontools ]; then
    tmp=$(mktemp)
    awk '
        BEGIN { done=0 }
        /^#?smartd_opts=/ {
            print "smartd_opts=\"--interval=3600\""
            done=1
            next
        }
        { print }
        END {
            if (!done) print "smartd_opts=\"--interval=3600\""
        }
    ' /etc/default/smartmontools > "$tmp"
    install -m 0644 "$tmp" /etc/default/smartmontools
    rm -f "$tmp"
else
    install -m 0644 "$ROOT/config/smartmontools" /etc/default/smartmontools
fi

# --- SMART amber timer: 1h so 10 min standby can expire ---
if [ -f /etc/systemd/system/smart-amber-led.timer ]; then
    backup_once /etc/systemd/system/smart-amber-led.timer bak.pre-disk-idle
    tmp=$(mktemp)
    sed 's/^OnUnitActiveSec=.*/OnUnitActiveSec=1h/' \
        /etc/systemd/system/smart-amber-led.timer > "$tmp"
    install -m 0644 "$tmp" /etc/systemd/system/smart-amber-led.timer
    rm -f "$tmp"
fi
if [ -f "$ROOT/scripts/smart-amber-led.timer" ]; then
    # Keep kit copy in sync when this script is the only updater on a live box.
    :
fi

# --- journald: volatile, 50M runtime cap ---
install -d /etc/systemd/journald.conf.d
backup_once /etc/systemd/journald.conf bak.pre-disk-idle
install -m 0644 "$ROOT/config/journald.conf" \
    /etc/systemd/journald.conf.d/ds115j.conf
# Live box previously set Storage=persistent in the main file; drop-in
# overrides it. Also comment the main Storage= line so a later package
# default cannot fight the drop-in in confusing ways.
if grep -q '^Storage=' /etc/systemd/journald.conf 2>/dev/null; then
    tmp=$(mktemp)
    sed 's/^Storage=persistent$/Storage=volatile/' /etc/systemd/journald.conf > "$tmp"
    # If it was already volatile, this is a no-op aside from rewrite.
    install -m 0644 "$tmp" /etc/systemd/journald.conf
    rm -f "$tmp"
fi
if grep -q '^RuntimeMaxUse=' /etc/systemd/journald.conf 2>/dev/null; then
    tmp=$(mktemp)
    sed 's/^RuntimeMaxUse=.*/RuntimeMaxUse=50M/' /etc/systemd/journald.conf > "$tmp"
    install -m 0644 "$tmp" /etc/systemd/journald.conf
    rm -f "$tmp"
fi

# --- fstab root: noatime,commit=60 (backup first; do not rename devices) ---
backup_once /etc/fstab bak.pre-disk-idle
tmp=$(mktemp)
awk '
    $1 == "LABEL=rootfs" && $2 == "/" {
        opts = $4
        if (opts !~ /(^|,)noatime(,|$)/) opts = opts ",noatime"
        if (opts ~ /(^|,)commit=[0-9]+(,|$)/)
            gsub(/commit=[0-9]+/, "commit=60", opts)
        else
            opts = opts ",commit=60"
        printf "%s\t%s\t%s\t%s\t%s\t%s\n", $1, $2, $3, opts, $5, $6
        next
    }
    { print }
' /etc/fstab > "$tmp"
install -m 0644 "$tmp" /etc/fstab
rm -f "$tmp"
if ! awk '$1=="LABEL=rootfs" && $2=="/" && $4 ~ /(^|,)noatime(,|$)/ && $4 ~ /(^|,)commit=60(,|$)/ { found=1 } END { exit found?0:1 }' /etc/fstab; then
    echo "fstab root line missing noatime,commit=60 after edit" >&2
    echo "restoring /etc/fstab.bak.pre-disk-idle if present" >&2
    if [ -f /etc/fstab.bak.pre-disk-idle ]; then
        cp -a /etc/fstab.bak.pre-disk-idle /etc/fstab
    fi
    exit 1
fi

REMOUNT_NOTE=
if mount -o remount,noatime,commit=60 /; then
    REMOUNT_NOTE="root remounted with noatime,commit=60"
else
    REMOUNT_NOTE="root remount failed; reboot needed for noatime,commit=60"
fi

# --- systemd oneshot ---
install -m 0644 "$ROOT/scripts/disk-idle.service" \
    /etc/systemd/system/disk-idle.service

systemctl daemon-reload
systemctl enable disk-idle.service
systemctl start disk-idle.service
systemctl restart systemd-journald.service
systemctl restart smartmontools.service
if systemctl is-enabled --quiet smart-amber-led.timer 2>/dev/null; then
    systemctl restart smart-amber-led.timer
fi

echo "install-disk-idle: $REMOUNT_NOTE"
echo "disk-idle.service: $(systemctl is-active disk-idle.service)"
echo "smartmontools: $(systemctl is-active smartmontools.service)"
"$HDPARM" -C /dev/sda || true
echo "Load_Cycle_Count note: WD Red increments LCC on each standby/wake."
echo "This kit sets -S 120 only; it does not set hdparm -B (APM)."
