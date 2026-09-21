# Optional Tweaks

Performance and convenience tweaks for DS115j. **None of these are required** — the base Debian system works without them. Install only what you need.

---

## 1. Sysctl: BBR + TCP Buffer Tuning

Switches TCP congestion control to BBR and increases buffer sizes for better GbE throughput.

### Install

```bash
NAS_PASS=<password> ./install-optional-tweaks.sh sysctl
```

### What it does

- Deploys `/etc/sysctl.d/99-ds115j-network.conf`
- Sets: `tcp_congestion_control = bbr`, `default_qdisc = fq`
- Increases TCP read/write buffers to 1 MiB max
- Enables TCP Fastopen (client + server)

### Verify

```bash
sysctl net.ipv4.tcp_congestion_control   # → bbr
sysctl net.core.rmem_max                 # → 1048576
```

### Remove

```bash
rm /etc/sysctl.d/99-ds115j-network.conf
sysctl --system   # reverts to kernel defaults
```

---

## 2. USB Auto-Mount

Automatically mount USB block devices to `/mnt/usb-<device>` when plugged in.

### Install

```bash
NAS_PASS=<password> ./install-optional-tweaks.sh usb
```

### What it does

- Deploys udev rule: `/etc/udev/rules.d/99-usb-automount.rules`
- Deploys helper script: `/usr/local/sbin/usb-automount.sh`
- Mounts to `/mnt/usb-sdX1` (rw, noatime) on plug-in
- Lazy-unmounts and removes mount point on unplug
- Idempotent: safe if the same device triggers udev multiple times
- **Skips devices already mounted (e.g. by UUID in `/etc/fstab`)**: the helper
  checks `findmnt /dev/sdX1` before mounting. If the device already has a
  mountpoint (fstab wins), it exits silently instead of mounting a second
  copy at `/mnt/usb-*`.

### Why it runs through systemd-run

`systemd-udevd.service` ships with `PrivateMounts=yes` on Debian 13. A
`mount(8)` started directly from a `RUN=` program then fails with
`mount: ...: permission denied` (EPERM) even as root, because it would mount
inside udevd's private name space. The rule therefore wraps the helper with
`systemd-run`, which escalates to PID 1 and mounts in the global name space.
This was verified live: the plain rule failed for `sdb4`/`sdc1` on every boot,
`systemd-run` version mounts them on plug-in.

### Verify

```bash
# Plug in a USB drive, then:
lsblk -o NAME,MOUNTPOINT | grep usb
# or
ls /mnt/usb-*
```

### Remove

```bash
rm /etc/udev/rules.d/99-usb-automount.rules
rm /usr/local/sbin/usb-automount.sh
udevadm control --reload-rules
```

---

## Install All

```bash
NAS_PASS=<password> ./install-optional-tweaks.sh all
```

## Hardware Note

These tweaks are optimized for DS115j (Marvell Armada 370, 256 MB RAM, single-core ARM). They work on any Debian system but buffer sizes and BBR tuning are specifically chosen for this hardware profile.

## Known Non-Functional

Wake-on-LAN is **not usable** on this hardware: the Ethernet controller is integrated into the Armada 370 SoC and loses power on `poweroff`, so Magic Packets cannot wake the device. Do not attempt to add a WoL tweak.