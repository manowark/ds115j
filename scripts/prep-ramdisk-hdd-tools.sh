#!/bin/bash
# Copy armhf mke2fs + libs into the TFTP ramdisk so the NAS can mkfs the HDD.
set -euo pipefail
ROOT=/root/ds115j
IR=$ROOT/initramfs
RFS=$ROOT/rootfs

mkdir -p "$IR/lib/arm-linux-gnueabihf" "$IR/sbin" "$IR/lib" "$IR/bin"
install -m 0755 "$RFS/usr/sbin/mke2fs" "$IR/sbin/mke2fs"
ln -sfn mke2fs "$IR/sbin/mkfs.ext4"

for so in libext2fs.so.2 libcom_err.so.2 libblkid.so.1 libuuid.so.1 libe2p.so.2 libc.so.6 \
          libext2fs.so.2.4 libcom_err.so.2.1 libblkid.so.1.1.0 libuuid.so.1.3.0 libe2p.so.2.3; do
    for d in "$RFS/lib/arm-linux-gnueabihf" "$RFS/usr/lib/arm-linux-gnueabihf"; do
        if [ -e "$d/$so" ]; then
            cp -a "$d/$so" "$IR/lib/arm-linux-gnueabihf/"
        fi
    done
done
# copy SONAME real files via glob
for d in "$RFS/lib/arm-linux-gnueabihf" "$RFS/usr/lib/arm-linux-gnueabihf"; do
    [ -d "$d" ] || continue
    for p in "$d"/libext2fs.so.2* "$d"/libcom_err.so.2* "$d"/libblkid.so.1* \
             "$d"/libuuid.so.1* "$d"/libe2p.so.2* "$d"/libc.so.6 "$d"/ld-linux-armhf.so.3; do
        [ -e "$p" ] && cp -a "$p" "$IR/lib/arm-linux-gnueabihf/"
    done
done
if [ -e "$RFS/lib/ld-linux-armhf.so.3" ]; then
    mkdir -p "$IR/lib"
    cp -a "$RFS/lib/ld-linux-armhf.so.3" "$IR/lib/"
fi
if [ -e "$RFS/lib/arm-linux-gnueabihf/ld-linux-armhf.so.3" ]; then
    mkdir -p "$IR/lib/arm-linux-gnueabihf"
    cp -a "$RFS/lib/arm-linux-gnueabihf/ld-linux-armhf.so.3" "$IR/lib/arm-linux-gnueabihf/"
fi

cd "$IR"
for a in nc tar fdisk gzip gunzip zcat wget dd mktemp; do
    ln -sfn /usr/bin/busybox "bin/$a"
    ln -sfn /usr/bin/busybox "sbin/$a"
done
install -m 0755 "$ROOT/scripts/dump-spi-linux.sh" "$IR/sbin/dump-spi-linux.sh"
install -m 0755 "$ROOT/scripts/extract-hdd.sh" "$IR/sbin/extract-hdd.sh"
echo "initramfs: mke2fs + nc/tar/fdisk"
ls -l "$IR/sbin/mke2fs" "$IR/sbin/mkfs.ext4" "$IR/sbin/extract-hdd.sh"
