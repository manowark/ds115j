#!/bin/bash
# Move a TFTP WRQ dump into this repository after U-Boot tftpput.
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SRC=${1:-$ROOT/.tftp-root/ds115j-spi-8m.bin}
DIR=${OUTDIR:-$ROOT/backups/spi}
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
