#!/bin/sh
# Serve the repository's known-good boot images over TFTP from a laptop.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TFTP_ROOT=${TFTP_ROOT:-"$ROOT/.tftp-root"}

mkdir -p "$TFTP_ROOT"
cp "$ROOT/boot/uImage-ds115j" \
   "$ROOT/boot/uRamdisk-hdd-ds115j" \
   "$ROOT/boot/uRamdisk-recovery-ds115j" \
   "$TFTP_ROOT/"

echo "TFTP root: $TFTP_ROOT"
echo "Serving repository boot images on UDP/69; stop with Ctrl-C."

case "$(uname -s)" in
    Darwin)
        exec sudo /usr/libexec/tftpd -L -s "$TFTP_ROOT"
        ;;
    Linux)
        if command -v in.tftpd >/dev/null 2>&1; then
            exec sudo in.tftpd --foreground --listen --address :69 --secure "$TFTP_ROOT"
        fi
        echo "Install tftpd-hpa, then rerun this script." >&2
        exit 1
        ;;
    *)
        echo "Unsupported host; serve $TFTP_ROOT with a TFTP daemon on UDP/69." >&2
        exit 1
        ;;
esac
