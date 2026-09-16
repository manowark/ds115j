#!/bin/bash
# Move a TFTP WRQ dump from /srv/tftp into backups/spi after U-Boot tftpput.
set -euo pipefail
SRC=${1:-/srv/tftp/ds115j-spi-8m.bin}
DIR=/root/ds115j/backups/spi
EXPECT=8388608
mkdir -p "$DIR"
[ -f "$SRC" ] || { echo "no $SRC"; exit 1; }
SIZE=$(stat -c %s "$SRC")
STAMP=$(date +%Y%m%d-%H%M%S)
DST=$DIR/ds115j-spi-8m-$STAMP.bin
mv "$SRC" "$DST"
sha256sum "$DST" | tee "$DST.sha256"
if [ "$SIZE" -ne "$EXPECT" ]; then
    echo "WARNING: $SIZE bytes, expected $EXPECT. Do not saveenv." >&2
    exit 1
fi
ln -sfn "$(basename "$DST")" "$DIR/ds115j-spi-8m.bin"
echo "OK $DST"
