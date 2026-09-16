# Optional Tweaks

Performance and convenience tweaks for DS115j. **None of these are required** — the base Debian system works without them. Install only what you need.

---

## 4. Wake-on-LAN

Enable Magic Packet wake-up on `eth0`. Allows powering on the NAS remotely from another device.

**Dependency:** `ethtool` (auto-installed)

### Install

```bash
./install-optional-tweaks.sh wol
```

### What it does

- Installs `ethtool` if missing
- Deploys systemd oneshot service: `/etc/systemd/system/wol.service` (runs `ethtool -s eth0 wol g` after `network.target`, survives reboots)
- Also deploys udev rule `/etc/udev/rules.d/70-wol-eth0.rules` as an early attempt (harmless if it fires before the interface is ready)

### Verify

```bash
ethtool eth0 | grep Wake-on
# Expected: Wake-on: g
```

### Remove

```bash
systemctl disable --now wol.service
rm /etc/systemd/system/wol.service /etc/udev/rules.d/70-wol-eth0.rules
ethtool -s eth0 wol d
```

---

## 5. Sysctl: BBR + TCP Buffer Tuning

Switches TCP congestion control to BBR and increases buffer sizes for better GbE throughput.

### Install

```bash
./install-optional-tweaks.sh sysctl
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

## 8. USB Auto-Mount

Automatically mount USB block devices to `/mnt/usb-<device>` when plugged in.

### Install

```bash
./install-optional-tweaks.sh usb
```

### What it does

- Deploys udev rule: `/etc/udev/rules.d/99-usb-automount.rules`
- Deploys helper script: `/usr/local/sbin/usb-automount.sh`
- Mounts to `/mnt/usb-sdX1` (rw, noatime) on plug-in
- Lazy-unmounts and removes mount point on unplug

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
./install-optional-tweaks.sh all
```

## Hardware Note

These tweaks are optimized for DS115j (Marvell Armada 370, 256 MB RAM, single-core ARM). They work on any Debian system but buffer sizes and BBR tuning are specifically chosen for this hardware profile.
