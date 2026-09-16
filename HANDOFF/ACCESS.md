# ACCESS — NAS, helper, UART, services

> Historical snapshot only. The helper is optional and may no longer exist.
> Use [`../docs/access.md`](../docs/access.md), serve TFTP from the laptop with
> `scripts/serve-tftp.sh`, and obtain every artifact from this Git clone.

Trusted LAN only. Do not publish these details off-LAN.

## Systems

| Role | Host / IP | How |
|---|---|---|
| **NAS (Debian)** | `ds115j` **`192.168.68.233/22`** | `ssh root@192.168.68.233` password **`ds115j`** |
| NAS DHCP (when lease exists) | historically **`192.168.68.62/22`** | same credentials; **as of 2026-09-15 19:50 UTC the lease had expired and `.62` was gone** |
| **Helper (this Pi)** | hostname `rpi` **`192.168.68.250/22`** | `ssh root@192.168.68.250` password **`ds115j`** (keys still work); project tree `/root/ds115j` |
| Gateway / DNS | **`192.168.68.1`** | default route; DNS also `1.1.1.1` |
| NAS MAC | **`00:11:32:4d:c3:b8`** | pinned by `.link` + ifupdown `pre-up` |
| Netmask | `255.255.252.0` (`/22`) | |

Owner preference: root/password SSH is acceptable on this LAN. Keep it LAN-only. Do not expose SSH to the Internet.

## UART from the Mac

```bash
screen /dev/cu.usbserial-BG01OOBA 115200
```

- Console: UART0 / `ttyS0`, 115200 8N1.
- Interrupt U-Boot during the 3-second countdown → `Marvell>>`.
- **Never leave a foreign/root `screen` holding this device.** Check and kill stale sessions before another operator needs UART.
- UART1 / `ttyS1` is the Synology PIC MCU (power-off, status LED, beeper). Do not hijack it for a second console.

## U-Boot / TFTP recovery addresses

```text
NAS ipaddr:     192.168.68.233
Helper serverip:192.168.68.250
Netmask:        255.255.252.0
Gateway:        192.168.68.1
Kernel load:    0x01000000
Ramdisk load:   0x02000000
```

Conceptual **current** local boot (do not rewrite `bootcmd` just to pretty-print; `printenv bootcmd` first):

```text
ide reset
ext2load ide 0:2 0x01000000 /boot/uImage-ds115j
ext2load ide 0:2 0x02000000 /boot/uRamdisk-hdd-ds115j
bootm 0x01000000 0x02000000
```

Kernel cmdline:

```text
console=ttyS0,115200 earlyprintk root=LABEL=rootfs rootwait rw panic=10
```

**NEVER** `ext2ls` / `ext2load` / probe **`ide 0:1`**. This U-Boot hangs. Use **`ide 0:2` only**. Disk command is **`ide`**, not `scsi`.

Historical TFTP recovery (helper must be up):

```text
tftpboot 0x01000000 uImage-ds115j
tftpboot 0x02000000 uRamdisk-hdd-ds115j      # HDD root
# or uRamdisk-recovery-ds115j / uRamdisk-ds115j for BusyBox recovery
bootm 0x01000000 0x02000000
```

Do not boot `/srv/tftp/uImage-nodtb` (no appended DTB).

## Helper services (verified listening 2026-09-15)

| Port | Service | State |
|---|---|---|
| TCP 22 | `sshd` | listening IPv4/IPv6 |
| UDP **69** | `tftpd-hpa` (`in.tftpd`), root `/srv/tftp` | **active**, enabled |
| TCP **45151** | `python3 /root/ds115j/scripts/spi-recv-daemon.py` | listening |
| TCP **45152** | `python3 -m http.server 45152 --bind 0.0.0.0 --directory /root/ds115j` | listening |

Historical URLs:

```text
SPI dump sink:  nc -w 60 192.168.68.250 45151 < ds115j-spi-8m.bin
Rootfs HTTP:    http://192.168.68.250:45152/rootfs-trixie-armhf.tar.gz
TFTP:           192.168.68.250:69
```

No DHCP/PXE/NFS server is part of this helper setup.

## Disk identifiers (do not reformat)

```text
sda1  64G   ext4  LABEL=rootfs  UUID=fc9ea304-14d5-4494-a117-7dfda838e18b  /
sda2  128M  ext2  LABEL=boot    UUID=eec9c4e3-7c83-40b6-af29-e28c4f228baa  (U-Boot source; not mounted in Linux by default)
~1.75 TiB unallocated
```

Physical sector size 4096; both partitions currently start off a 4 KiB boundary (`sda1` start 63).

## Live NAS listeners (2026-09-15 19:50 UTC)

Only **sshd :22** (IPv4 and IPv6). No Samba/NFS yet.

## Password handling

- NAS root password **`ds115j`** is the working credential.
- Helper SSH (enabled 2026-09-15): `ssh root@192.168.68.250` password **`ds115j`**. Root was locked (`passwd -S` = `L`, shadow `*`); password was **newly set** to `ds115j`. `PermitRootLogin yes`, `PasswordAuthentication yes`, `PubkeyAuthentication yes` via `/etc/ssh/sshd_config.d/99-root-password.conf`. Do not disable key auth.
- Do not print these LAN passwords in public tickets. They are repeated here because the next AI must actually log in.
