#!/bin/sh
# Apply DS115j login/network/SSH fixes to a mounted Debian root filesystem.
# Run from the recovery initramfs after mounting LABEL=rootfs at /mnt:
#   /sbin/fix-hdd-root.sh /mnt
set -eu

TARGET=${1:-/mnt}
BB=${BB:-/usr/bin/busybox}
ROOT_HASH='$6$ds115j$8thWTncFzUFWIKn749shWZByOQahw6JQz8VV/A0F1f5V.1y/CInssbonl7xQ0nFWyeJdSieGu6cLOOuSO0.UV0'

[ -d "$TARGET/etc" ] || {
    echo "ERROR: $TARGET is not a mounted root filesystem" >&2
    exit 1
}
$BB mount -o remount,rw "$TARGET" 2>/dev/null || true
probe="$TARGET/etc/.ds115j-write-test.$$"
$BB touch "$probe" 2>/dev/null || {
    echo "ERROR: $TARGET is not writable; remount it read-write first" >&2
    exit 1
}
$BB rm -f "$probe"

$BB mkdir -p \
    "$TARGET/etc/network/interfaces.d" \
    "$TARGET/etc/ssh/sshd_config.d" \
    "$TARGET/etc/systemd/network" \
    "$TARGET/etc/systemd/system/getty.target.wants" \
    "$TARGET/etc/systemd/system/multi-user.target.wants" \
    "$TARGET/etc/systemd/system/network-online.target.wants" \
    "$TARGET/dev"

cat > "$TARGET/etc/network/interfaces" <<'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
	address 192.168.68.233/22
	gateway 192.168.68.1
	pre-up /sbin/modprobe marvell
	pre-up /sbin/modprobe mvmdio
	pre-up /sbin/modprobe mvneta
	pre-up /sbin/ip link set dev eth0 address 00:11:32:4d:c3:b8
	dns-nameservers 192.168.68.1 1.1.1.1
EOF

cat > "$TARGET/etc/resolv.conf" <<'EOF'
nameserver 192.168.68.1
nameserver 1.1.1.1
EOF

cat > "$TARGET/etc/systemd/network/10-ds115j-eth0.link" <<'EOF'
[Match]
OriginalName=eth0

[Link]
MACAddress=00:11:32:4d:c3:b8
NamePolicy=keep
EOF

# OpenSSH refuses to start without the main config. Drop-ins alone are not enough.
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
$BB chmod 0644 "$TARGET/etc/ssh/sshd_config"

cat > "$TARGET/etc/ssh/sshd_config.d/ds115j.conf" <<'EOF'
PermitRootLogin yes
PasswordAuthentication yes
UsePAM yes
EOF

if [ -f "$TARGET/etc/shadow" ]; then
    tmp="$TARGET/etc/.shadow.ds115j.$$"
    $BB awk -F: -v OFS=: -v hash="$ROOT_HASH" '
        $1 == "root" { $2=hash; $3=1; $4=0; $5=99999; $6=7; $7=""; $8=""; $9=""; found=1 }
        { print }
        END { if (!found) print "root",hash,1,0,99999,7,"","","" }
    ' "$TARGET/etc/shadow" > "$tmp"
    $BB chown 0:42 "$tmp"
    $BB chmod 0640 "$tmp"
    $BB mv "$tmp" "$TARGET/etc/shadow"
else
    echo "ERROR: $TARGET/etc/shadow is missing" >&2
    exit 1
fi
if [ -f "$TARGET/etc/passwd" ]; then
    tmp="$TARGET/etc/.passwd.ds115j.$$"
    $BB awk -F: -v OFS=: '$1 == "root" { $2="x" } { print }' \
        "$TARGET/etc/passwd" > "$tmp"
    $BB chown 0:0 "$tmp"
    $BB chmod 0644 "$tmp"
    $BB mv "$tmp" "$TARGET/etc/passwd"
else
    echo "ERROR: $TARGET/etc/passwd is missing" >&2
    exit 1
fi

$BB ln -sfn /usr/lib/systemd/system/serial-getty@.service \
    "$TARGET/etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service"
$BB ln -sfn /usr/lib/systemd/system/networking.service \
    "$TARGET/etc/systemd/system/multi-user.target.wants/networking.service"
$BB ln -sfn /usr/lib/systemd/system/networking.service \
    "$TARGET/etc/systemd/system/network-online.target.wants/networking.service"
$BB ln -sfn /usr/lib/systemd/system/ssh.service \
    "$TARGET/etc/systemd/system/multi-user.target.wants/ssh.service"
$BB rm -f "$TARGET/etc/systemd/system/multi-user.target.wants/sshd.service"

# Host keys: chroot ssh-keygen needs real char devices. Never create a regular
# file named /dev/null (that "hack" breaks ssh-keygen and pollutes the HDD).
# Prefer bind-mounting the live /dev (devtmpfs on the ramdisk). Always leave
# mknod char nodes on the target after unbind.
for n in null zero random urandom; do
    if [ -e "$TARGET/dev/$n" ] && [ ! -c "$TARGET/dev/$n" ]; then
        $BB rm -f "$TARGET/dev/$n"
    fi
done
dev_bound=0
if [ -c /dev/null ]; then
    if $BB mount -o bind /dev "$TARGET/dev"; then
        dev_bound=1
    fi
fi
if [ "$dev_bound" != 1 ]; then
    [ -c "$TARGET/dev/null" ]    || $BB mknod -m 666 "$TARGET/dev/null"    c 1 3
    [ -c "$TARGET/dev/zero" ]    || $BB mknod -m 666 "$TARGET/dev/zero"    c 1 5
    [ -c "$TARGET/dev/random" ]  || $BB mknod -m 666 "$TARGET/dev/random"  c 1 8
    [ -c "$TARGET/dev/urandom" ] || $BB mknod -m 666 "$TARGET/dev/urandom" c 1 9
fi
if [ -x "$TARGET/usr/bin/ssh-keygen" ]; then
    if ! $BB chroot "$TARGET" /usr/bin/ssh-keygen -A; then
        echo "WARN: ssh-keygen -A failed in $TARGET (sshd_config was still installed)" >&2
    fi
else
    echo "WARN: $TARGET/usr/bin/ssh-keygen is missing" >&2
fi
if [ "$dev_bound" = 1 ]; then
    $BB umount "$TARGET/dev" || true
fi
[ -c "$TARGET/dev/null" ]    || $BB mknod -m 666 "$TARGET/dev/null"    c 1 3
[ -c "$TARGET/dev/zero" ]    || $BB mknod -m 666 "$TARGET/dev/zero"    c 1 5
[ -c "$TARGET/dev/random" ]  || $BB mknod -m 666 "$TARGET/dev/random"  c 1 8
[ -c "$TARGET/dev/urandom" ] || $BB mknod -m 666 "$TARGET/dev/urandom" c 1 9

$BB sync
echo "Applied DS115j root password, ttyS0, network, MAC, DNS, and SSH fixes to $TARGET"
