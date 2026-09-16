#!/bin/sh
# Reconstruct the rootfs archive from Git-friendly parts and verify it.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PARTS="$ROOT/rootfs/rootfs-trixie-armhf.tar.gz.part-*"
OUT=${1:-"$ROOT/rootfs-trixie-armhf.tar.gz"}
KIT="$ROOT/ds115j-install-kit.tar.gz"
EXPECTED=9d869bf8f45f6f3908097aece847bb2d1bde4a6213801cb8460cdb83f9a30eb6

set -- $PARTS
[ -f "$1" ] || {
    echo "Rootfs parts are missing from $ROOT/rootfs" >&2
    exit 1
}

cat "$@" > "$OUT"
ACTUAL=$(shasum -a 256 "$OUT" | awk '{print $1}')
if [ "$ACTUAL" != "$EXPECTED" ]; then
    rm -f "$OUT"
    echo "Rootfs checksum mismatch: expected $EXPECTED, got $ACTUAL" >&2
    exit 1
fi

echo "Reconstructed and verified: $OUT"

# Small, self-contained second-stage kit served beside the rootfs. Keeping it
# local avoids depending on GitHub from the NAS and guarantees config/script
# versions match this checkout.
tar -C "$ROOT" -czf "$KIT" README.md config modules scripts
echo "Built userspace kit: $KIT"
