#!/bin/sh
# Run ON the NAS (stock DSM or Debian). Helper only stores a copy of this file.
# Dumps the 8 MiB SPI NOR. Does not write flash. Does not saveenv.
set -eu

HELPER=192.168.68.250
PORT=45151
OUT=/tmp/ds115j-spi-8m.bin
EXPECT=8388608

echo "=== /proc/mtd ==="
cat /proc/mtd || true

dump_char() {
    # Prefer read-only nodes.
    if [ -e /dev/mtd0ro ]; then
        echo "dd from /dev/mtd0ro"
        dd if=/dev/mtd0ro of="$OUT" bs=65536 status=none
        return
    fi
    if [ -e /dev/mtd0 ]; then
        echo "dd from /dev/mtd0 (read; do not use flash_erase)"
        dd if=/dev/mtd0 of="$OUT" bs=65536 status=none
        return
    fi
    if [ -e /dev/mtdblock0 ]; then
        echo "dd from /dev/mtdblock0"
        dd if=/dev/mtdblock0 of="$OUT" bs=65536 status=none
        return
    fi
    return 1
}

if ! dump_char; then
    echo "No whole-chip MTD. Concatenating mtd* in numeric order (RedBoot layout)."
    : > "$OUT"
    i=0
    while [ "$i" -lt 16 ]; do
        src=
        [ -e /dev/mtd${i}ro ] && src=/dev/mtd${i}ro
        [ -z "$src" ] && [ -e /dev/mtd$i ] && src=/dev/mtd$i
        if [ -n "$src" ]; then
            echo "append $src"
            dd if="$src" bs=65536 status=none >> "$OUT"
        fi
        i=$((i + 1))
    done
fi

SIZE=$(wc -c < "$OUT")
echo "local dump $SIZE bytes"
if [ "$SIZE" -ne "$EXPECT" ]; then
    echo "WARNING: not 8 MiB. Check /proc/mtd; do not saveenv."
fi

echo "Sending to helper $HELPER:$PORT -> /root/ds115j/backups/spi/"
echo "(helper: spi-recv-daemon.py or recv-spi.sh must be listening)"
if command -v nc >/dev/null 2>&1; then
    nc -w 30 "$HELPER" "$PORT" < "$OUT" || busybox nc -w 30 "$HELPER" "$PORT" < "$OUT"
else
    echo "No nc. Copy $OUT off the NAS another way (scp, USB)."
    exit 2
fi
echo "done"
