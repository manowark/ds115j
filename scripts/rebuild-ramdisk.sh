#!/bin/bash
# Historical helper script. Rebuilds recovery ramdisk from an unpacked
# /root/ds115j/initramfs tree (not in git). Supported images are in boot/.
# Rebuild the DS115j TFTP ramdisk from /root/ds115j/initramfs and install it
# into /srv/tftp. Does not touch the NAS, U-Boot env, or any running service.
set -euo pipefail

KVER=6.12.107+deb13-armmp
ROOT=/root/ds115j
IRFS=$ROOT/initramfs
OUT=$ROOT/kernel
TFTP=/srv/tftp

# modules.dep must match whatever .ko files are currently in the tree.
depmod -b "$IRFS" "$KVER"

# Guard: stray editor/backup files must never end up in the cpio.
if find "$IRFS" \( -name '*.bak' -o -name '*.bak-*' -o -name '*~' \) -print | grep -q .; then
    echo "ERROR: backup files found inside $IRFS" >&2
    find "$IRFS" \( -name '*.bak' -o -name '*.bak-*' -o -name '*~' \) -print >&2
    exit 1
fi

cd "$IRFS"
find . -print0 \
    | cpio --null --create --format=newc --quiet \
    | gzip -9 > "$OUT/initramfs-ds115j.gz"

mkimage -A arm -O linux -T ramdisk -C gzip \
    -a 0x04000000 -e 0x04000000 -n "DS115j test initramfs" \
    -d "$OUT/initramfs-ds115j.gz" \
    "$OUT/uRamdisk-ds115j"

install -m 0644 "$OUT/uRamdisk-ds115j" "$TFTP/uRamdisk-ds115j"
install -m 0644 "$OUT/uRamdisk-ds115j" "$TFTP/uRamdisk-recovery-ds115j"

echo
echo "built:"
ls -la "$OUT/initramfs-ds115j.gz" "$OUT/uRamdisk-ds115j" \
    "$TFTP/uRamdisk-ds115j" "$TFTP/uRamdisk-recovery-ds115j"
md5sum "$OUT/uRamdisk-ds115j" "$TFTP/uRamdisk-ds115j" \
    "$TFTP/uRamdisk-recovery-ds115j"
