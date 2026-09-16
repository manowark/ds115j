# Install / reinstall with UART (manual)

Simple hand path. UART connected. No Cursor agents required.

Two cases:

1. **New DS115j** (stock DSM, blank disk, or unknown) → Debian like the current daily-ready box.
2. **Reinstall this device** (the NAS already on `.233`) without casually destroying `sda3` data.

Read [landmines.md](landmines.md) first. Recovery-only (already Debian, just won’t boot): [recovery.md](recovery.md).

## 0. Desk setup

```text
UART:   115200 8N1   (Mac: screen /dev/cu.usbserial-BG01OOBA 115200)
        Console is UART0 / ttyS0. UART1 / ttyS1 is the PIC MCU — leave it alone.
NAS IP: 192.168.68.233/22     netmask 255.255.252.0     gateway 192.168.68.1
Laptop: example 192.168.68.251/22   serves files from this repository
Password (LAN): ds115j
```

Kill stale `screen` sessions before you start (`screen -ls`).

**U-Boot disk is `ide`, not `scsi`.**

**Never type `ide 0:1`.** This U-Boot **hangs**. Boot files are only on **`ide 0:2`** (`sda2`, 128 MiB ext2 `LABEL=boot`). Root is `sda1` (`LABEL=rootfs`). Data is `sda3` (`LABEL=data` → `/srv/data`).

Do not `saveenv`, `sf erase`, `sf write`, `bubt`, or `fw_setenv`.

Current good images (also in `boot/` of this repo):

```text
uImage-ds115j            SHA-256 5ea71e0bc69a17ae269e278eedc28288702f1259edffefd97d420e01141ae3e8
uRamdisk-hdd-ds115j      SHA-256 dbbd30ec2c3772e2816eaa5e3295b0580a357fc93458dcb3bf063bf7bf65cd75
uRamdisk-recovery-ds115j SHA-256 cc9e6bc063a1247c3f370a87238f6ff544ff01ba145aed19f537b13d2810dd96
```

## 1. Interrupt U-Boot

Power on (or reboot). During the **3-second** countdown, hit a key → `Marvell>>`.

```text
Marvell>> printenv bootcmd
```

You are only going to **type** boot commands. Do not `saveenv`.

## 2. Serve and TFTP the kernel from the laptop

On the Mac, clone this repository and give its LAN interface an address on the
same `/22`, for example `192.168.68.251/22`. From the repository root:

```bash
scripts/serve-tftp.sh
```

This stages and serves the three known-good files from `boot/` using macOS
`/usr/libexec/tftpd`. It prompts for `sudo` because TFTP uses UDP/69. In U-Boot:

```text
Marvell>> setenv ipaddr 192.168.68.233
Marvell>> setenv serverip 192.168.68.251
Marvell>> setenv netmask 255.255.252.0
Marvell>> tftpboot 0x01000000 uImage-ds115j
Marvell>> tftpboot 0x02000000 uRamdisk-recovery-ds115j
Marvell>> bootm 0x01000000 0x02000000
```

Use `uRamdisk-hdd-ds115j` instead of recovery **only** when `sda1` already has a working Debian root (`LABEL=rootfs`).

Do not boot `uImage-nodtb`.

## 3. Partition the disk

You should now be in **BusyBox recovery** (or Linux if you used the HDD ramdisk). Confirm:

```sh
cat /proc/partitions
# expect sda
```

### 3a. Reinstall **this** device (keep data if you can)

**Do not** `dd` the whole disk. **Do not** run `scripts/extract-hdd.sh` (it wipes `sda` and creates a **single** partition — stale).

Live layout (2 TB WD Red) is snapshotted in `config/sda.sfdisk`:

```text
sda1  ~64 GiB   ext4  LABEL=rootfs   Debian /
sda2  128 MiB   ext2  LABEL=boot     U-Boot files only  (ide 0:2)
sda3  rest      ext4  LABEL=data     /srv/data
```

Typical reinstall:

1. Leave `sda2` and `sda3` alone if they still look right (`blkid`).
2. Only remake **root**: `mkfs.ext4 -L rootfs /dev/sda1` (this wipes Debian on `sda1`).
3. If `sda2` is missing or corrupt, recreate **128 MiB ext2 `LABEL=boot` as partition 2** — never swap 1 and 2.
4. Recreate `sda3` only if you intend to destroy `/srv/data`.

If `sda2` is fine, skip to [§5](#5-install-boot-images-on-sda2) after filling `sda1`.

### 3b. New disk / stock DSM wipe (destroys everything)

U-Boot needs **MBR (dos)** and **partition 2 = boot**. Prefer 1 MiB alignment on a blank disk (the live NAS still has historical start-sector 63; do not clone that to a new drive unless you are restoring this exact disk).

Example (BusyBox `fdisk` / `sfdisk`; adjust sizes to the disk):

```text
sda1  64G   type 83   later: mkfs.ext4 -L rootfs /dev/sda1
sda2  128M  type 83   later: mkfs.ext2 -L boot   /dev/sda2
sda3  rest  type 83   later: mkfs.ext4 -L data   /dev/sda3
```

Then:

```sh
mkfs.ext4 -L rootfs /dev/sda1
mkfs.ext2 -L boot   /dev/sda2
mkfs.ext4 -L data   /dev/sda3
```

## 4. Install Debian userspace onto `sda1`

The complete rootfs is in Git as two files below 95 MB. On the laptop,
reconstruct it and serve the repository over HTTP:

```bash
scripts/reconstruct-rootfs.sh
python3 -m http.server 45152 --bind 0.0.0.0 --directory "$PWD"
```

The reconstruction script verifies SHA-256
`9d869bf8f45f6f3908097aece847bb2d1bde4a6213801cb8460cdb83f9a30eb6`.
Then, from recovery:

```sh
mkdir -p /mnt
mount /dev/sda1 /mnt
wget -O /tmp/rootfs.tgz http://192.168.68.251:45152/rootfs-trixie-armhf.tar.gz
tar -C /mnt -xzf /tmp/rootfs.tgz
# overlay this kit's config (network, fstab) — see config/
cp /path/to/kit/config/fstab /mnt/etc/fstab
# if the tarball still has static-only eth0, replace with config/interfaces
sync
umount /mnt
```

`scripts/configure-rootfs.sh` is the off-device rootfs overlay (hostname
`ds115j`, serial getty, SSH, root hash for password `ds115j`).
`scripts/fix-hdd-root.sh` can be copied into the recovery ramdisk and run as
`fix-hdd-root.sh /mnt` if SSH/network/login are wrong.

**MAC:** live unit is `00:11:32:4d:c3:b8`. On a **new** chassis, put **that unit’s** sticker MAC into `config/interfaces` and `config/10-ds115j-eth0.link` — do not clone the old MAC onto two boxes.

The shipped rootfs already includes the
`6.12.107+deb13-armmp` module tree matching `boot/uImage-ds115j`. Do not replace
it with a newer ABI during installation. Continue with
[§6](#6-install-userspace-scripts-mcu-fan-smart-poweroff).

## 5. Install boot images on `sda2`

From a running Debian (preferred) use [`scripts/deploy-boot.sh`](../scripts/deploy-boot.sh). It mounts `sda2`, keeps a few `*.pre-*` copies, verifies SHA-256, and **never** touches `sda1`/`sda3`.

From this kit, make a bundle directory:

```sh
mkdir -p /root/boot-deploy/5ea71e0b-noalarm
cp uImage-ds115j uRamdisk-hdd-ds115j SHA256SUMS /root/boot-deploy/5ea71e0b-noalarm/
# SHA256SUMS uses names without the "boot/" prefix; rename to MANIFEST if you like:
cp SHA256SUMS /root/boot-deploy/5ea71e0b-noalarm/MANIFEST
/root/deploy-boot.sh /root/boot-deploy/5ea71e0b-noalarm deploy
```

From recovery, by hand:

```sh
mkdir -p /mnt/boot
mount /dev/sda2 /mnt
mkdir -p /mnt/boot
# copy uImage-ds115j and uRamdisk-hdd-ds115j into /mnt/boot
# fetch from the laptop TFTP/HTTP server or copy from the cloned repository
sha256sum /mnt/boot/uImage-ds115j /mnt/boot/uRamdisk-hdd-ds115j
sync
umount /mnt
```

U-Boot load path is **`/boot/uImage-ds115j` on `ide 0:2`**, which is Linux `/boot` **on `sda2`**, not `/boot` on `sda1`.

## 6. Install userspace scripts (MCU LED, fan, SMART amber, poweroff)

Once Debian on `sda1` is up (UART login or SSH):

```sh
# copy this repo onto the NAS, then:
sh scripts/install-userspace.sh
```

That installs:

| Piece | Files |
|-------|--------|
| MCU LEDs/beep | `syno-mcu.sh`, `syno-mcu-boot.sh`, two systemd units |
| Fan | `syno-fan.sh` + `syno-fan.service` (never pwm 0; never unbind `gpio-fan`) |
| SMART amber | `smart-amber-led.sh` + timer/service + `config/smartd.conf` |
| Soft poweroff | `modules/qnap-poweroff-ds115j.ko` → `/lib/modules/$(uname -r)/extra/` + `modules-load.d` |

Network snapshot: `config/interfaces` (DHCP + **`.233` on `eth0:1`**). Never `ifdown eth0` from the only SSH session. Never `auto eth0:1`.

Also enable `dbus` if `reboot`/`timedatectl` fail with “Failed to connect to system scope bus”.

Packages you will want from apt (Internet): `smartmontools`, `chrony`, `zram-tools` (then `config/zramswap`), `dbus`. Journal cap: `config/journald.conf`.

## 7. First local boot (no TFTP)

Interrupt U-Boot again and **type** (do not `saveenv` unless you already have a reviewed SPI procedure):

```text
ide reset
ext2load ide 0:2 0x01000000 /boot/uImage-ds115j
ext2load ide 0:2 0x02000000 /boot/uRamdisk-hdd-ds115j
setenv bootargs 'console=ttyS0,115200 earlyprintk root=LABEL=rootfs rootwait rw panic=10'
bootm 0x01000000 0x02000000
```

If that works, the existing `bootcmd` on this unit already does the same from `ide 0:2`. On a **new** unit, stock DSM `bootcmd` will not. Leave env alone until you are ready for a dedicated, dump-verified env change — until then, interrupt and type, or keep using TFTP.

## 8. Network `.233` pattern

Target: SSH always at `192.168.68.233`, plus DHCP on `eth0` when a server answers.

Use `config/interfaces` and `config/10-ds115j-eth0.link`. Cosmetic `Address already assigned` in logs is OK.

## 9. Checks

```sh
uname -a                    # 6.12.107+deb13-armmp
ip -4 addr                  # .233 on eth0:1
systemctl --failed          # empty
systemctl is-active syno-fan.service syno-mcu-boot.service smartd.service
lsmod | grep qnap_poweroff
test -e /sys/firmware/devicetree/base/gpio-fan/alarm-gpios && echo BAD || echo ABSENT
sha256sum /mnt/boot/uImage-ds115j   # if sda2 mounted; expect 5ea71e0b…
```

LED map: [led-behaviour.md](led-behaviour.md). SMART amber test: [smart-amber-led.md](smart-amber-led.md).

## 10. SPI dump (new device, before any env experiment)

Keep a verified **8388608-byte** dump. This repo has `firmware/spi/ds115j-spi-8m-20260915-124830.bin` (SHA `cfbdc0dd…`) from **this** unit — useful as a reference, not a random flash image for a different board. Helper scripts: `scripts/dump-spi-linux.sh`, `scripts/spi-recv-daemon.py`. **Dumping is fine. Writing SPI is not routine.**

## Gaps

- Full debootstrap / first `apt-get` needs **Internet on the NAS**.
- Rootfs extraction itself is offline after cloning; first-boot package
  configuration still needs Internet.
- The matching kernel module tree is inside the split rootfs archive; the
  custom poweroff module is also present separately in `modules/`.
- Stock U-Boot `bootcmd` on a brand-new DSM box will not load Debian until you either type the `ext2load ide 0:2` sequence each boot or perform a **separately reviewed** env change (SPI landmine).
