#!/bin/sh
# STALE — do not use on the live NAS and do not use for a new daily-ready
# install. This script WIPES /dev/sda and creates a SINGLE partition.
# Current layout is sda1 root / sda2 boot / sda3 data. See docs/install-uart.md.
#
# Kept only as history. Original comment: run on ramdisk after SPI dump.
# Wipes /dev/sda and extracts Debian. Does not flash SPI. Does not saveenv.
set -eu

DISK=/dev/sda
MNT=/mnt
TARBALL=${1:-/tmp/rootfs-trixie-armhf.tar.gz}

echo "=== DS115j HDD extract ==="
echo "DESTROYS all data on $DISK. Run only after backups/spi has 8388608 bytes."
echo
cat /proc/partitions

if [ ! -b "$DISK" ]; then
    echo "No $DISK (sata_mv?). Abort."
    exit 1
fi

echo "Writing a new MBR + one primary partition..."
dd if=/dev/zero of="$DISK" bs=1M count=8
printf 'o\nn\np\n1\n\n\nw\n' | fdisk "$DISK"

part=${DISK}1
i=0
while [ ! -b "$part" ] && [ "$i" -lt 25 ]; do
    sleep 1
    i=$((i + 1))
done
[ -b "$part" ] || { echo "No $part after fdisk"; exit 1; }

mke2fs -t ext4 -F -L rootfs "$part"

mkdir -p "$MNT"
umount "$MNT" 2>/dev/null || true
mount "$part" "$MNT"

[ -f "$TARBALL" ] || {
    echo "Missing $TARBALL. Reconstruct it from this repository first." >&2
    exit 1
}
tar -C "$MNT" -xzf "$TARBALL"
sync
echo "Extracted onto $part LABEL=rootfs"
ls "$MNT"
echo
echo "Manual U-Boot (no saveenv):"
echo "  setenv bootargs 'console=ttyS0,115200 root=LABEL=rootfs rootwait rw'"
echo "  tftpboot 0x01000000 uImage-ds115j"
echo "  bootm 0x01000000"
