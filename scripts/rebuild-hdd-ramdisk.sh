#!/bin/bash
# Historical helper script. Rebuilds HDD ramdisk from /root/ds115j/initramfs-hdd
# (not in git). Supported image is boot/uRamdisk-hdd-ds115j.
# Build the DS115j HDD-root initramfs and install it into TFTP.
# The recovery image is separate: /srv/tftp/uRamdisk-recovery-ds115j.
set -euo pipefail

KVER=6.12.107+deb13-armmp
ROOT=/root/ds115j
IRFS=$ROOT/initramfs-hdd
OUT=$ROOT/kernel
TFTP=/srv/tftp

depmod -b "$IRFS" "$KVER"

if find "$IRFS" \( -name '*.bak' -o -name '*.bak-*' -o -name '*~' \) -print | grep -q .; then
    echo "ERROR: backup files found inside $IRFS" >&2
    exit 1
fi

cd "$IRFS"
find . -print0 \
    | cpio --null --create --format=newc --quiet \
    | gzip -9 > "$OUT/initramfs-hdd-ds115j.gz"

mkimage -A arm -O linux -T ramdisk -C gzip \
    -a 0x04000000 -e 0x04000000 -n "DS115j HDD root initramfs" \
    -d "$OUT/initramfs-hdd-ds115j.gz" \
    "$OUT/uRamdisk-hdd-ds115j"

install -m 0644 "$OUT/uRamdisk-hdd-ds115j" "$TFTP/uRamdisk-hdd-ds115j"

stat -c '%n %s bytes' "$OUT/uRamdisk-hdd-ds115j" "$TFTP/uRamdisk-hdd-ds115j"
md5sum "$OUT/uRamdisk-hdd-ds115j" "$TFTP/uRamdisk-hdd-ds115j"
