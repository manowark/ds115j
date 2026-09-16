#!/bin/bash
# Listen on TCP 45151 and write one dump into backups/spi.
# Prefer spi-recv-daemon.py for repeated dumps.
set -euo pipefail
OUTDIR=/root/ds115j/backups/spi
mkdir -p "$OUTDIR"
STAMP=$(date +%Y%m%d-%H%M%S)
OUT=$OUTDIR/ds115j-spi-8m-$STAMP.bin
EXPECT=8388608
PORT=45151

echo "Listening on 0.0.0.0:$PORT -> $OUT"
echo "NAS: nc -w 30 192.168.68.250 $PORT < /tmp/ds115j-spi-8m.bin"

python3 - "$PORT" "$OUT" <<'PY'
import socket, sys
port, path = int(sys.argv[1]), sys.argv[2]
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("0.0.0.0", port)); s.listen(1)
print("python recv ready", flush=True)
c, a = s.accept(); print("connection from", a, flush=True)
with open(path, "wb") as f:
    while True:
        b = c.recv(1024 * 1024)
        if not b:
            break
        f.write(b)
c.close(); s.close()
PY

SIZE=$(stat -c %s "$OUT")
echo "received $SIZE bytes -> $OUT"
sha256sum "$OUT" | tee "$OUT.sha256"
if [ "$SIZE" -ne "$EXPECT" ]; then
    echo "WARNING: expected $EXPECT bytes (8 MiB). Do not saveenv." >&2
    exit 1
fi
ln -sfn "$(basename "$OUT")" "$OUTDIR/ds115j-spi-8m.bin"
ln -sfn "$(basename "$OUT")" /root/ds115j/spi-dumps/ds115j-spi-8m.bin 2>/dev/null || true
echo "OK. Canonical: $OUTDIR/ds115j-spi-8m.bin"
