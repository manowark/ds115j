#!/bin/sh
# usb-automount.sh — mount/unmount USB drives triggered by udev
# Usage: usb-automount.sh {mount|umount} <kernel-name>
# e.g.:  usb-automount.sh mount sdb1
#        usb-automount.sh umount sdb1

set -e

ACTION="$1"
DEVICE="$2"
MNT="/mnt/usb-${DEVICE}"

case "$ACTION" in
  mount)
    # Idempotent: skip if already mounted at our target path
    if mountpoint -q "$MNT" 2>/dev/null; then
      exit 0
    fi
    # Skip if the device is already mounted anywhere (e.g. the same disk is
    # listed in /etc/fstab by UUID). Mounting one device at two paths with
    # different options is legal but redundant; fstab wins.
    if findmnt -rno TARGET "/dev/${DEVICE}" >/dev/null 2>&1; then
      exit 0
    fi
    mkdir -p "$MNT"
    # Try rw first; fall back to ro if device is read-only (e.g. USB-RO switch)
    if mount -o rw,noatime "/dev/${DEVICE}" "$MNT" 2>/dev/null; then
      : # mounted rw
    elif mount -o ro,noatime "/dev/${DEVICE}" "$MNT" 2>/dev/null; then
      : # mounted ro
    else
      rmdir "$MNT" 2>/dev/null
      exit 1
    fi
    ;;
  umount)
    # Lazy unmount — safe if something still has a handle open
    umount -l "$MNT" 2>/dev/null || true
    rmdir "$MNT" 2>/dev/null || true
    ;;
  *)
    echo "Usage: $0 {mount|umount} <kernel-name>" >&2
    exit 1
    ;;
esac
