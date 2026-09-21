# Install / reinstall with UART (manual)

Simple hand path. UART connected. No Cursor agents required.

Two cases:

1. **New DS115j** (stock DSM, blank disk, or unknown) → Debian like the current daily-ready box.
2. **Reinstall this device** (the NAS already on `.233`) without casually destroying `sda3` data.

This page is the complete happy path. You do not need a helper machine, an
agent, or another document: only this repository on the laptop, Internet
access from the NAS for `apt`, and the UART/TFTP connection below.

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

Never type `ide 0:1`, never set the fan to `0`, never run `ifdown eth0`, and
never write SPI (`sf erase`, `sf write`, `bubt`, `fw_setenv`). The default
boot method below does not use `saveenv`.

Current good images (also in `boot/` of this repo). The `uImage-ds115j` is the
**v2 with the USB VBUS fix** (`usb-regulator@2` on MPP44, always-on; no
`alarm-gpios`) verified live 2026-09-20 — this is the only image to deploy:

```text
uImage-ds115j            SHA-256 6b58d6eee97005845923167d5fe481035b7031195935bd632cdbe29ae75ed0f6
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
same `/22`, for example `192.168.68.251/22`. The included network files use
the live unit's MAC `00:11:32:4d:c3:b8`; for a different chassis, first replace
that value in `config/interfaces`, `config/interfaces-bootstrap`, and
`config/10-ds115j-eth0.link` with the new unit's sticker MAC. From the
repository root:

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

Create a 1 MiB-aligned MBR layout with the BusyBox `fdisk` included in the
recovery ramdisk:

```sh
fdisk /dev/sda
```

At the prompts:

1. If `fdisk` asks `Do you want to create a disklabel?`, answer `y`.
2. At `Command`, type `o` to create a DOS/MBR label.
3. Type `n`, `p`, `1`, `2048`, `+64G` for `sda1`.
4. Type `n`, `p`, `2`, Enter for the default start, `+128M` for `sda2`.
5. Type `n`, `p`, `3`, Enter, Enter for `sda3` using the remaining space.
6. Type `p`. Verify `sda1` starts at sector `2048`, `sda2` is partition 2
   and 128 MiB, and `sda3` consumes the remainder.
7. Only if that listing is correct, type `w`. Otherwise type `q` and retry.

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
cd /path/to/ds115j
scripts/reconstruct-rootfs.sh
python3 -m http.server 45152 --bind 0.0.0.0 --directory "$PWD"
```

The reconstruction script verifies SHA-256
`9d869bf8f45f6f3908097aece847bb2d1bde4a6213801cb8460cdb83f9a30eb6`
and also creates `ds115j-install-kit.tar.gz`. Run HTTP in a second laptop
terminal (or stop TFTP after recovery has booted); keep UART in its own
terminal.
Then, from recovery:

```sh
mkdir -p /mnt
mount /dev/sda1 /mnt
wget -O /tmp/rootfs.tgz http://192.168.68.251:45152/rootfs-trixie-armhf.tar.gz
tar -C /mnt -xzf /tmp/rootfs.tgz
mkdir -p /mnt/etc/network /mnt/etc/systemd/network /mnt/etc/apt /mnt/srv/data
wget -O /mnt/etc/network/interfaces \
  http://192.168.68.251:45152/config/interfaces-bootstrap
wget -O /mnt/etc/systemd/network/10-ds115j-eth0.link \
  http://192.168.68.251:45152/config/10-ds115j-eth0.link
wget -O /mnt/etc/fstab \
  http://192.168.68.251:45152/config/fstab
wget -O /mnt/etc/apt/sources.list \
  http://192.168.68.251:45152/config/sources.list
sync
umount /mnt
```

Those four files provide static `.233` for the first boot (the rootfs does not
yet have a DHCP client), stable MAC naming, `LABEL=data` at `/srv/data`, and
Debian trixie, updates, and security repositories. The installer in §6 adds
DHCP while retaining `.233` as `eth0:1`; there is deliberately no
`auto eth0:1 inet static` stanza.

The shipped rootfs already includes the
`6.12.107+deb13-armmp` module tree matching `boot/uImage-ds115j`. Do not replace
it with a newer ABI during installation. Continue with §5.

## 5. Install boot images on `sda2`

Keep the laptop HTTP server from §4 running. From recovery:

```sh
mkdir -p /mnt
mount /dev/sda2 /mnt
mkdir -p /mnt/boot
wget -O /mnt/boot/uImage-ds115j \
  http://192.168.68.251:45152/boot/uImage-ds115j
wget -O /mnt/boot/uRamdisk-hdd-ds115j \
  http://192.168.68.251:45152/boot/uRamdisk-hdd-ds115j
echo '6b58d6eee97005845923167d5fe481035b7031195935bd632cdbe29ae75ed0f6  /mnt/boot/uImage-ds115j' | sha256sum -c -
echo 'dbbd30ec2c3772e2816eaa5e3295b0580a357fc93458dcb3bf063bf7bf65cd75  /mnt/boot/uRamdisk-hdd-ds115j' | sha256sum -c -
sync
umount /mnt
```

U-Boot load path is **`/boot/uImage-ds115j` on `ide 0:2`**, which is Linux `/boot` **on `sda2`**, not `/boot` on `sda1`.

## 6. First local boot and daily-ready userspace

Interrupt U-Boot and type these commands. Do this on every boot until you
deliberately choose the optional persistent method in §8:

```text
ide reset
ext2load ide 0:2 0x01000000 /boot/uImage-ds115j
ext2load ide 0:2 0x02000000 /boot/uRamdisk-hdd-ds115j
setenv bootargs 'console=ttyS0,115200 earlyprintk root=LABEL=rootfs rootwait rw panic=10'
bootm 0x01000000 0x02000000
```

Log in on UART as `root` / `ds115j`. Wait for the one-time Debian second stage
to finish, confirm Internet works, fetch the version-matched kit from the
laptop HTTP server, and run the installer:

```sh
while [ ! -e /etc/ds115j-second-stage-done ]; do
  systemctl is-failed --quiet ds115j-second-stage.service && {
    systemctl status ds115j-second-stage.service --no-pager
    exit 1
  }
  sleep 5
done
ping -c 3 deb.debian.org
cd /root
wget -O ds115j-install-kit.tar.gz \
  http://192.168.68.251:45152/ds115j-install-kit.tar.gz
mkdir -p ds115j-kit
tar -C ds115j-kit -xzf ds115j-install-kit.tar.gz
cd ds115j-kit
sh scripts/install-userspace.sh
```

`install-userspace.sh` explicitly installs `chrony`, `zram-tools`,
`smartmontools`, `hdparm`, `dbus`, `ifupdown`, the DHCP client, `kmod`, and CA
certificates. It installs trixie/updates/security apt sources, the DHCP +
`.233` network config and `.link`, creates `/srv/data`, installs the
`LABEL=data` fstab entry, then installs and enables:

| Piece | Files |
|-------|--------|
| MCU LEDs/beep | `syno-mcu.sh`, `syno-mcu-boot.sh`, two systemd units |
| Fan | `syno-fan.sh` + `syno-fan.service` (never pwm 0; never unbind `gpio-fan`) |
| SMART amber | `smart-amber-led.sh` + timer/service + `config/smartd.conf` (`-n standby,q`, 1 h timer) |
| HDD idle | `disk-idle.service` (`hdparm -S 120` = 10 min) via `scripts/install-disk-idle.sh` |
| Soft poweroff | `modules/qnap-poweroff-ds115j.ko` + `modules-load.d` |
| Power button | `syno-powerbtn.sh` + `syno-powerbtn.service` + `syno-powerbtn.conf` (armed `30`), `syno-powerbtn-arm.sh` + `.service` (PIC arming at boot) — see `docs/power-button.md` |
| DSM parity tuning | `90-ds115j-tune.conf` (sysctl), `usbcore-autosuspend-off.conf`, `90-ds115j-watchdog.conf` (SoC watchdog via systemd), `rtc-power-schedule.sh` — see `docs/dsm-os-features.md` |
| Base services | `chrony`, `zramswap`, `smartmontools`, `dbus`, `networking` |

The power-button daemon ships **armed** (`TRIGGER_BYTES="30"` in `config`…/`scripts/syno-powerbtn.conf`): the front button performs a clean `poweroff` via `qnap_poweroff_ds115j`. Verified live 2026-09-21: the PIC reports `0x30` on a press and the arming **survives power-off** (PIC stays on a standby rail). The `syno-powerbtn-arm` boot unit re-sends the DSM rc bytes (`echo 4`/`echo 9`) defensively after every boot (idempotent; needed only if the PIC ever loses its latched state, e.g. after a long wall-power loss).

The installer never restarts networking, so it does not drop the current UART
or SSH session. Reboot and type the same U-Boot commands once more to apply all
boot-time settings.

```sh
reboot
```

## 7. Default safe boot (works without SPI changes)

For normal daily use, keep UART attached, interrupt the three-second countdown,
and type:

```text
ide reset
ext2load ide 0:2 0x01000000 /boot/uImage-ds115j
ext2load ide 0:2 0x02000000 /boot/uRamdisk-hdd-ds115j
setenv bootargs 'console=ttyS0,115200 earlyprintk root=LABEL=rootfs rootwait rw panic=10'
bootm 0x01000000 0x02000000
```

This is the default supported path and works on both a stock and an already
converted unit without changing SPI.

## 8. Optional unattended boot — high-risk `saveenv`

Skip this section unless unattended cold boot is essential. Synology placed
the U-Boot environment at SPI offset `0x00100000`, inside the stock kernel
area. A bad write can brick the NAS. Keep UART attached throughout.

Before the one permitted `saveenv`, make a **board-specific** 8 MiB dump:

1. On the laptop, from this repository, run `scripts/recv-spi.sh` and leave it
   listening on TCP 45151.
2. On the NAS run
   `RECEIVER=192.168.68.251 sh /root/ds115j-kit/scripts/dump-spi-linux.sh`.
3. The receiver verifies the size and writes the dump under `backups/spi/`.
   Copy that `.bin` into `firmware/spi/` with a unique chassis/date name, then
   from `firmware/spi/` run
   `sha256sum UNIQUE-NAME.bin > UNIQUE-NAME.bin.sha256` followed by
   `sha256sum -c UNIQUE-NAME.bin.sha256`. Keep both files in the repository
   and another copy outside the NAS; `wc -c UNIQUE-NAME.bin` must report
   exactly `8388608`.
4. Reboot with UART, type the §7 commands, and confirm they boot successfully.
5. At the next `Marvell>>` prompt, inspect `printenv bootargs bootcmd`. Only
   then set the exact values proven by the live DS115j:

```text
setenv bootargs 'console=ttyS0,115200 earlyprintk root=LABEL=rootfs rootwait rw panic=10'
setenv bootcmd 'ide reset; ext2load ide 0:2 0x01000000 /boot/uImage-ds115j; ext2load ide 0:2 0x02000000 /boot/uRamdisk-hdd-ds115j; bootm 0x01000000 0x02000000'
printenv bootargs bootcmd
saveenv
```

Power-cycle once with UART attached. If anything differs from those exact
values, do **not** run `saveenv`; continue using §7.

## 9. Checks

```sh
uname -r                    # 6.12.107+deb13-armmp
ip -4 addr show dev eth0    # DHCP plus .233 labelled eth0:1
findmnt /                    # rw,noatime,commit=60 on LABEL=rootfs
findmnt /srv/data            # source carrying LABEL=data, rw,noatime
apt-get update               # trixie + updates + security succeed
chronyc tracking             # Leap status: Normal
swapon --show                # /dev/zram0, priority 100
smartctl -H /dev/sda         # SMART overall-health PASSED on a healthy disk
systemctl --failed           # empty
systemctl is-active networking chrony zramswap smartmontools dbus
systemctl is-active syno-fan.service syno-mcu-boot-begin.service
systemctl is-active syno-mcu-boot.service smart-amber-led.timer
systemctl is-active disk-idle.service
systemctl is-active syno-powerbtn.service syno-powerbtn-arm.service
grep '^TRIGGER_BYTES=' /etc/syno-powerbtn.conf   # "30" = armed
journalctl -u syno-powerbtn --no-pager -n 3      # "ARMED, trigger byte(s): 30"
sysctl net.core.somaxconn                        # 65535 (DSM parity)
cat /sys/module/usbcore/parameters/autosuspend   # -1 (USB storage never sleeps)
cat /sys/class/watchdog/watchdog0/state           # active (systemd feeds; 60 s timeout)
hdparm -C /dev/sda           # active/idle just after boot; standby after 10+ min quiet
/usr/local/sbin/syno-mcu.sh ping
lsmod | grep qnap_poweroff
test -e /sys/firmware/devicetree/base/gpio-fan/alarm-gpios && echo BAD || echo ABSENT
test "$(cat /sys/class/leds/synology:amber:disk/brightness)" = 0
PWM=$(for p in /sys/class/hwmon/hwmon*/pwm1; do
  [ -e "$p" ] && [ -e "${p%/*}/fan1_target" ] && { echo "$p"; break; }
done)
test -n "$PWM" && test "$(cat "$PWM")" -gt 0
```

The ready state is: blue power steady, status green steady after one short
beep, bay green controlled by SATA, bay amber off while SMART is healthy. The
fan must never read `0`. The **front power button performs a clean power-off**
(armed daemon reads `0x30` from the PIC and runs `systemctl poweroff`, which
cuts PSU power through `qnap_poweroff_ds115j`); test it only while physically
present to press the button afterward to power the NAS back on.

## 10. Daily-ready result

When every §9 check passes, the NAS is daily-ready: local HDD boot, DHCP plus
permanent `.233`, `/srv/data`, working trixie apt, SMART monitoring and amber
fault indication, 10-minute HDD spin-down (`docs/disk-idle.md`), chrony, zram,
MCU boot/ready LEDs and beep, temperature fan control, the soft-poweroff
module, and a **front power button that cleanly powers the NAS off**
(`docs/power-button.md`). The only external requirement after rootfs extraction
is Internet access for the explicit apt installation. Journald is volatile
(logs gone on reboot) so the disk can sleep.
