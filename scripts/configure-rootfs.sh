#!/bin/bash
# Overlay hostname, fstab, network, serial getty, ssh, and kernel modules
# into a locally built armhf rootfs. Safe to re-run. Does not touch the NAS.
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TARGET=${TARGET:-$ROOT/rootfs-build}
export TARGET
KVER=6.12.107+deb13-armmp
MODSRC=${MODSRC:-$ROOT/kernel/usr/lib/modules/$KVER}
ROOT_HASH='$6$ds115j$8thWTncFzUFWIKn749shWZByOQahw6JQz8VV/A0F1f5V.1y/CInssbonl7xQ0nFWyeJdSieGu6cLOOuSO0.UV0'

if [ ! -d "$TARGET/etc" ]; then
    echo "No rootfs at $TARGET — run bootstrap-rootfs.sh first." >&2
    exit 1
fi

install -d "$TARGET/etc/network/interfaces.d" \
           "$TARGET/etc/systemd/system/getty.target.wants" \
           "$TARGET/etc/systemd/system/multi-user.target.wants" \
           "$TARGET/etc/systemd/system/network-online.target.wants" \
           "$TARGET/etc/ssh/sshd_config.d" \
           "$TARGET/etc/systemd/network" \
           "$TARGET/etc/modules-load.d" \
           "$TARGET/etc/apt" \
           "$TARGET/root" \
           "$TARGET/srv/data" \
           "$TARGET/lib/modules"

cat > "$TARGET/etc/hostname" <<'EOF'
ds115j
EOF

cat > "$TARGET/etc/hosts" <<'EOF'
127.0.0.1	localhost
127.0.1.1	ds115j
::1		localhost ip6-localhost ip6-loopback
EOF

install -m 0644 "$ROOT/config/fstab" "$TARGET/etc/fstab"
install -m 0644 "$ROOT/config/interfaces" "$TARGET/etc/network/interfaces"
install -m 0644 "$ROOT/config/sources.list" "$TARGET/etc/apt/sources.list"

cat > "$TARGET/etc/resolv.conf" <<'EOF'
nameserver 192.168.68.1
nameserver 1.1.1.1
EOF

install -m 0644 "$ROOT/config/10-ds115j-eth0.link" \
    "$TARGET/etc/systemd/network/10-ds115j-eth0.link"

# OpenSSH will not start without the main file (drop-ins are not enough).
cat > "$TARGET/etc/ssh/sshd_config" <<'EOF'
# DS115j temporary sshd config. OpenSSH will not start without this file.
# PermitRootLogin / PasswordAuthentication are for bring-up only; tighten later.

Include /etc/ssh/sshd_config.d/*.conf

Port 22
AddressFamily any
ListenAddress 0.0.0.0
ListenAddress ::

HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

# Temporary: password root login from the LAN. Change the password and
# switch to keys before exposing this host beyond 192.168.68.0/22.
PermitRootLogin yes
PasswordAuthentication yes
PermitEmptyPasswords no
KbdInteractiveAuthentication no
UsePAM yes
PrintMotd no
X11Forwarding no
AcceptEnv LANG LC_* COLORTERM NO_COLOR
Subsystem sftp /usr/lib/openssh/sftp-server
EOF
chmod 0644 "$TARGET/etc/ssh/sshd_config"

cat > "$TARGET/etc/ssh/sshd_config.d/ds115j.conf" <<'EOF'
PermitRootLogin yes
PasswordAuthentication yes
UsePAM yes
EOF

# Enable services explicitly because this rootfs was assembled chrootless and
# package maintainer scripts did not run.
if [ -e "$TARGET/usr/lib/systemd/system/serial-getty@.service" ]; then
    ln -sfn /usr/lib/systemd/system/serial-getty@.service \
        "$TARGET/etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service"
fi
ln -sfn /usr/lib/systemd/system/networking.service \
    "$TARGET/etc/systemd/system/multi-user.target.wants/networking.service"
ln -sfn /usr/lib/systemd/system/networking.service \
    "$TARGET/etc/systemd/system/network-online.target.wants/networking.service"
ln -sfn /usr/lib/systemd/system/ssh.service \
    "$TARGET/etc/systemd/system/multi-user.target.wants/ssh.service"
rm -f "$TARGET/etc/systemd/system/multi-user.target.wants/sshd.service"

# This is `openssl passwd -6 -salt ds115j ds115j`, verified at build time.
# Writing the known hash avoids depending on armhf binaries on this 16K host.
HASH=$ROOT_HASH
export HASH
if [ -f "$TARGET/etc/shadow" ]; then
    python3 <<'PY'
import os
from pathlib import Path
path = Path(os.environ["TARGET"] + "/etc/shadow")
h = os.environ["HASH"]
lines = [ln for ln in path.read_text().splitlines() if ln.strip() and not ln.startswith("root:")]
lines.insert(0, f"root:{h}:1:0:99999:7:::")
path.write_text("\n".join(lines) + "\n")
PY
    chown root:shadow "$TARGET/etc/shadow" 2>/dev/null || true
    chmod 640 "$TARGET/etc/shadow"
else
    echo "WARN: no /etc/shadow yet; root password must be set on the NAS." >&2
fi
if [ -f "$TARGET/etc/passwd" ]; then
    python3 <<'PY'
import os
from pathlib import Path
path = Path(os.environ["TARGET"] + "/etc/passwd")
lines = []
for line in path.read_text().splitlines():
    fields = line.split(":")
    if fields[0] == "root":
        fields[1] = "x"
        line = ":".join(fields)
    lines.append(line)
path.write_text("\n".join(lines) + "\n")
PY
    chmod 0644 "$TARGET/etc/passwd"
fi

# SSH host key files are architecture-independent. Generate them with the
# host ssh-keygen because armhf package postinst scripts did not run.
# Use -A -f PREFIX (no chroot) so we never depend on TARGET/dev/null.
if command -v ssh-keygen >/dev/null; then
    ssh-keygen -A -f "$TARGET"
fi

# Kernel + HDD initramfs for later local U-Boot load (ide, not scsi).
install -d "$TARGET/boot"
for img in uImage-ds115j uRamdisk-hdd-ds115j; do
    install -m 0644 "$ROOT/boot/$img" "$TARGET/boot/$img"
done

if [ -d "$MODSRC" ]; then
    echo "Installing $KVER modules into rootfs..."
    rm -rf "$TARGET/lib/modules/$KVER"
    mkdir -p "$TARGET/lib/modules"
    cp -a "$MODSRC" "$TARGET/lib/modules/$KVER"
    # Debian packages ship .ko.xz; depmod understands them.
    # Host kmod can index the modules; no armhf execution.
    depmod -b "$TARGET" "$KVER"
fi

cat > "$TARGET/etc/modules-load.d/ds115j.conf" <<'EOF'
marvell
mvmdio
mvneta
sata_mv
sd_mod
ehci-orion
ehci-hcd
usb-storage
spi-orion
spi-nor
mtdblock
ofpart
ext4
EOF

cat > "$TARGET/root/README-ds115j.txt" <<'EOF'
Debian trixie armhf for Synology DS115j (built off-device).

Temporary root password: ds115j
Change it: passwd

eth0 uses DHCP plus permanent 192.168.68.233/22 on label eth0:1.

This tree is meant for sda1 on the NAS HDD (U-Boot ide, not scsi).
See the repository's docs/install-uart.md for the three-part disk layout.

Kernel cmdline (U-Boot, do not saveenv until SPI is dumped):
  console=ttyS0,115200 root=LABEL=rootfs rootwait rw

Do not flash SPI. Do not run saveenv until an 8 MiB dump is safely copied off-device.
EOF

echo "configure-rootfs: done"
