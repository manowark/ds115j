# RECOVERY-RUNBOOK — DS115j (operator + next-AI)

> Historical copy. Use [`../docs/recovery.md`](../docs/recovery.md), which
> serves repository artifacts from the laptop and has no helper dependency.

Goal: **restore bootability or get back onto the running system** using U-Boot + local `ide 0:2` and/or helper TFTP, **without ever** probing `ide 0:1`, writing SPI (`sf`/`saveenv`/`bubt`/`fw_setenv`), or reformatting. Last resort vs. bricking: keep U-Boot env untouched, boot from known-good images.

## Access (full: ACCESS.md)

| Role | DNS / IP | UART / TFTP |
|---|---|---|
| NAS | `ds115j` 192.168.68.233/22 | UART0 ttyS0 115200 (screen /dev/cu.usbserial-BG01OOBA 115200) |
| Helper | `rpi` 192.168.68.250/22 | UDP/69 tftpd /srv/tftp |
| Gateway/DNS | 192.168.68.1 | — |

## Boot image inventory (verified 2026-09-16)

All uImages are Debian 6.12.107 `Linux/ARM` legacy images, load/entry `0x008000`. Ramdisk uImages load/entry `0x04000000`.

| Image (sha256[16]) | sda2:/boot (U-Boot source) | helper /srv/tftp | helper artifacts | note |
|---|---|---|---|---|
| `5ea71e0bc69a17ae` | **`uImage-ds115j`** (current) | **`uImage-ds115j`** (TFTP default) + `uImage-ds115j.new-noalarm` | `uImage-ds115j.new-noalarm` | **NO alarm-gpios (MUST-1)**; TFTP default promoted 2026-09-16 11:31 UTC |
| `c1688fda25f1472d` | `uImage-ds115j.pre-noalarm-20260916` | `uImage-ds115j.pre-alarm-gpios-c1688fda` + `uImage-ds115j.pre-noalarm-20260916` | `uImage-ds115j` | previous; **alarm-gpios present** — do not TFTP-boot as default |
| `69e60698a993b487` | `uImage-ds115j.pre-poweroff-i2c-20260915` | `uImage-ds115j.pre-poweroff-i2c-20260915-1638` | — | older; alarm-gpios present |
| `dbbd30ec2c3772e2` | **`uRamdisk-hdd-ds115j`** | `uRamdisk-hdd-ds115j` | `uRamdisk-hdd-ds115j` | HDD-root initramfs (mounts LABEL=rootfs) |
| `cc9e6bc063a1247c` | — | `uRamdisk-recovery-ds115j` | — | BusyBox recovery (fsck-ready) |
| `cf192fe77338447a` | — | `ds115j-poweroff-i2c.dtb` | — | peripherals DTB (power-off, not current boot) |
| `3354e4fb61ecb21a` | — (in rootfs /lib/modules) | `qnap-poweroff-ds115j.ko` | `qnap-poweroff-ds115j.ko` | power-off module, vermagic must match kernel |

Rule: kernel uImage, DTB, HDD initramfs and power-off `.ko` are **one compatibility set** — change together. `uImage-ds115j` and `uRamdisk-hdd-ds115j` must ship as a pair (versions tracked in /root/ds115j/boot-deploy/).

## UART console

```bash
screen -S nas-console /dev/cu.usbserial-BG01OOBA 115200
```
- U-Boot: hit a key during the 3 s countdown → `Marvell>>`.
- Linux: `console=ttyS0,115200`, serial getty = login prompt.
- **Before** using UART on the Mac, kill stale `screen` sessions (`screen -ls; screen -X -S <old> quit`). UART1/ttyS1 is the Synology PIC MCU — leave it alone.

## Scenario A — NAS running, SSH lost

Stay calm; the system is probably fine, the lease changed or a greenfield stalled.
1. UART console (above). Log in.
2. Diagnose: `ip -4 addr; ip route` — is `.233` present? Default route?
3. **Never `ifdown eth0`/`systemctl stop networking` blindly** (only SSH out). Repair without cycling the link:
   - If DHCP: `dhclient -v eth0` (idempotent) then keep `.233` pinned for fallback.
   - Bring the static `.233` up in addition (interface alias or `ip addr add 192.168.68.233/22 dev eth0`), not replacing DHCP.
4. Confirm: `ping -c2 192.168.68.250`; `systemctl --failed`; `ssh root@192.168.68.233`.

## Scenario B — NAS fails to boot (hang/panic)

Interrupt U-Boot to `Marvell>>`. Then **prefer local `sda2` rollback first**; TFTP only if that fails or partition is gone.

Boot rollback, one command-line at a time (safe — only `ide 0:2`):

```text
ide reset
ext2load ide 0:2 0x01000000 /boot/uImage-ds115j.pre-noalarm-20260916
ext2load ide 0:2 0x02000000 /boot/uRamdisk-hdd-ds115j
bootm 0x01000000 0x02000000
```
The current images are booted with the same flow, `/boot/uImage-ds115j` + `/boot/uRamdisk-hdd-ds115j` (see ACCESS.md conceptual bootcmd).

If boot completes, promote the rollback image later (Section E) using `deploy-boot.sh prev`.

TFTP fallback (helper `.250` must be up; `/root/ds115j/HANDOFF/HELPER-TREE.md` shows how to (re)start `tftpd-hpa` / http):

```text
setenv ipaddr 192.168.68.233
setenv serverip 192.168.68.250
tftpboot 0x01000000 uImage-ds115j
tftpboot 0x02000000 uRamdisk-hdd-ds115j
bootm 0x01000000 0x02000000
```
Do **not** use `/srv/tftp/uImage-nodtb` (no appended DTB). For full recovery with tools (fsck etc.) substitute `uRamdisk-recovery-ds115j`.

After a TFTP boot, the running root is still `sda1` (HDD initramfs) — or BusyBox for recovery ramdisk.

## Scenario C — sda2 (boot) corrupt / not found

1. TFTP boot `uImage-ds115j` + `uRamdisk-recovery-ds115j` (above).
2. Inside BusyBox recovery: `e2fsck -f /dev/sda2` (LABEL=boot, 128 MiB ext2). If clean or repaired:
   - `mount /dev/sda2 /mnt` (rw), re-install images from TFTP (`tftp -g -r <file> 192.168.68.250`, or scp http://192.168.68.250:45152/), verify sha256, `sync; umount`.
   - Reboot: `exit`/`reboot -f`.
3. If sda2 layout is lost but sda1 rootfs intact: recreate partition (start after 4 KiB boundary, e.g. MB alignment) + mkfs.ext2 LABEL=boot, then install images. Never touch sda1 (rootfs) or sda3 data.

## Scenario D — helper `.250` unavailable

Sole fallback is local `sda2` (Section B). Keep an extra copy of the boot set on a USB stick / Mac:
`/srv/tftp/{uImage-ds115j,uImage-ds115j.new-noalarm,uRamdisk-hdd-ds115j,uRamdisk-recovery-ds115j,qnap-poweroff-ds115j.ko}`.

## E. Versioned boot deploy / rollback (automated)

Use `/root/ds115j/scripts/deploy-boot.sh` (run it **on the NAS**; bundle copied from helper). Summary:

```bash
# on NAS (no dummy bundle dir):
/root/deploy-boot.sh list
/root/deploy-boot.sh dry-prev          # print hashes; no write, no reboot
# /root/deploy-boot.sh prev            # WRITES sda2 current uImage to newest .pre-*
#                                      # Today that is c1688fda (alarm-gpios). UART required to reboot.
/root/deploy-boot.sh /root/boot-deploy/<VER>-<TAG> deploy
```
The script mounts `sda2` ({mount,install,sync,umount}), keeps previous uImages as `uImage-ds115j.pre-YYYYMMDD-HHMMSS-<tag>` (max 3), read-back-verifies sha256 **before** umount, and never touches sda1/sda3. If no ramdisk `.pre-*` exists, `prev` keeps the live ramdisk. Keep sda2 hash == helper `/srv/tftp/uImage-ds115j` hash.

## F. Post-recovery verification checklist

```bash
uname -a                       # 6.12.107+deb13-armmp expected
df -h / | grep -q LABEL=rootfs || true
ip -4 addr show eth0          # .233 present (or DHCP lease)
systemctl --failed            # empty
lsmod | grep qnap_poweroff    # loaded
free -h | awk "/Swap/"        # zram zram0 lz4 2G active
sha256sum -c /root/boot-deploy/<VER>-<TAG>/MANIFEST   # boot set hash check on the device side
```
Also re-run the health gate (MUST-10) before declaring the box cured.

## Repo of record (before/after)

Record in `/root/ds115j/HANDOFF/HISTORY.md`: what broke, images used (full sha256), whether it touched helper / sda1 / sda2 / U-Boot / SPI. U-Boot env and SPI must stay **untouched** by any recovery.
