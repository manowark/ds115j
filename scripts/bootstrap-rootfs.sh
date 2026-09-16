#!/bin/bash
# Build a Debian trixie armhf rootfs from Debian mirrors on a Linux laptop.
# Does not talk to the NAS, does not flash, does not saveenv.
#
# Chrootless mode does not execute armhf binaries on the host.
# Remaining dpkg --configure -a happens on first boot on the NAS (4 KiB).
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TARGET=${TARGET:-$ROOT/rootfs-build}
DIST=trixie
ARCH=armhf
MIRROR=${MIRROR:-http://deb.debian.org/debian}
LOG=$ROOT/rootfs-bootstrap.log
INCLUDE=systemd,systemd-sysv,openssh-server,sudo,vim-tiny,usbutils,mtd-utils,ifupdown,ca-certificates,kmod,udev,iproute2,iputils-ping,fdisk,e2fsprogs,wget

exec > >(tee -a "$LOG") 2>&1
echo "=== $(date -Is) bootstrap-rootfs start ==="

ready() {
    [ -e "$TARGET/sbin/init" ] && [ -d "$TARGET/etc/apt" ] && [ ! -d "$TARGET/debootstrap" ] && [ -e "$TARGET/usr/bin/dpkg" ]
}

if ready; then
    echo "Rootfs already present at $TARGET — skipping unpack."
    "$ROOT/scripts/configure-rootfs.sh"
    exit 0
fi

if [ -d "$TARGET" ] && [ -d "$TARGET/debootstrap" ]; then
    BAK=$ROOT/rootfs.failed-qemu-$(date +%Y%m%d-%H%M%S)
    echo "Moving incomplete debootstrap tree aside -> $BAK"
    mv "$TARGET" "$BAK"
fi

mkdir -p "$TARGET"

if ! command -v mmdebstrap >/dev/null; then
    echo "Need mmdebstrap (apt install mmdebstrap)." >&2
    exit 1
fi

echo "=== mmdebstrap --mode=chrootless $DIST $ARCH ==="
mmdebstrap --verbose --skip=check/empty --skip=check/chrootless \
    --arch="$ARCH" --variant=minbase --mode=chrootless \
    --include="$INCLUDE" \
    "$DIST" "$TARGET" "$MIRROR"

# First-boot hook: finish package configuration on the NAS (4K pages).
install -d "$TARGET/etc/systemd/system/multi-user.target.wants" \
           "$TARGET/usr/local/libexec"
cat > "$TARGET/usr/local/libexec/ds115j-second-stage.sh" <<'EOF'
#!/bin/sh
# Runs once on the NAS. Safe no-op after /etc/ds115j-second-stage-done exists.
set -e
[ -e /etc/ds115j-second-stage-done ] && exit 0
export DEBIAN_FRONTEND=noninteractive
[ ! -x /usr/bin/dpkg ] || dpkg --configure -a
[ ! -x /usr/bin/apt-get ] || apt-get -y -f install
date -u > /etc/ds115j-second-stage-done
systemctl disable ds115j-second-stage.service 2>/dev/null || true
EOF
chmod 0755 "$TARGET/usr/local/libexec/ds115j-second-stage.sh"

cat > "$TARGET/etc/systemd/system/ds115j-second-stage.service" <<'EOF'
[Unit]
Description=Finish Debian package configuration on DS115j
Wants=network-online.target
After=local-fs.target network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/ds115j-second-stage.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
ln -sfn /etc/systemd/system/ds115j-second-stage.service \
    "$TARGET/etc/systemd/system/multi-user.target.wants/ds115j-second-stage.service"

"$ROOT/scripts/configure-rootfs.sh"

echo "=== $(date -Is) bootstrap-rootfs done ==="
du -sh "$TARGET"
echo "Rootfs built at $TARGET. See docs/install-uart.md."
