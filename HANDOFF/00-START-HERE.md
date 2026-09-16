# 00 — START HERE (DS115j Debian handoff on helper `.250`)

You are continuing a **Synology DS115j → Debian 13 (trixie armhf)** conversion. Hardware enablement, local HDD boot, and MUST-1…12 daily-NAS gates are **in place** (MUST-8 skipped by owner). Remaining work is backup/restore drill and burn-in — not re-doing udev or networking.

This package lives **on the helper**, not only in a Cursor store:

```text
/root/ds115j/HANDOFF/          ← you are here (primary)
/root/ds115j/                  ← full build/recovery tree (~3.0 GiB)
/srv/tftp/                     ← live TFTP recovery images
```

Entry: [`README.md`](README.md). Paste prompt: [`PASTE-FOR-NEXT-AI.md`](PASTE-FOR-NEXT-AI.md). Live probe: [`CURRENT-STATE.md`](CURRENT-STATE.md). Reboot verify 12:06 UTC: [`COLD-BOOT-VERIFY.md`](COLD-BOOT-VERIFY.md) (**daily-ready YES**; `reboot` not PSU `poweroff`). Independent audit: [`FULL-MUST-AUDIT.md`](FULL-MUST-AUDIT.md) (11:22 UTC; MUST-12 follow-up later the same day).

## What this is

| Item | Value |
|---|---|
| Hardware | Synology **DS115j**, Marvell **Armada 370** (MV6710 A1), 1× PJ4B @ 800 MHz, **256 MiB** DDR |
| Disk | 1× WD Red **WD20EFRX-68EUZN0** ~2 TB (`sda`) |
| OS live | Debian **13.7 / trixie** armhf, kernel `6.12.107+deb13-armmp` |
| Boot | U-Boot `ide` (not `scsi`); **`ext2load ide 0:2`** from `sda2` LABEL=`boot` |
| Root | `sda1` 64 GiB ext4 LABEL=`rootfs` UUID `fc9ea304-14d5-4494-a117-7dfda838e18b` |
| Ethernet | PHY **88E1318S** (`0x01410e90`), **`rgmii-id`**, MAC `00:11:32:4d:c3:b8` |
| Helper | Raspberry Pi hostname `rpi`, **`192.168.68.250/22`** |

## Access (see [`ACCESS.md`](ACCESS.md))

```text
NAS:    ssh root@192.168.68.233     password: ds115j
Helper: ssh root@192.168.68.250     password: ds115j  (pubkey still accepted)
UART:   screen /dev/cu.usbserial-BG01OOBA 115200   (from the Mac)
TFTP:   UDP 69  tftpd-hpa  /srv/tftp
SPI rx: TCP 45151  python3 /root/ds115j/scripts/spi-recv-daemon.py
HTTP:   TCP 45152  python3 -m http.server … --directory /root/ds115j
```

Permanent IPv4 `.233` is on **`eth0:1`**. DHCP on `eth0` moves (`.62`, `.77`, …). Never `ifdown eth0` from the only SSH session.

## Where everything lives

| Path | Contents |
|---|---|
| `/root/ds115j/HANDOFF/00-START-HERE.md` | this file |
| `/root/ds115j/HANDOFF/ACCESS.md` | credentials, IPs, UART, ports |
| `/root/ds115j/HANDOFF/LANDMINES.md` | never-do list |
| `/root/ds115j/HANDOFF/MUST-FIXES.md` | MUST-1…12 (8 skip) |
| `/root/ds115j/HANDOFF/CURRENT-STATE.md` | live NAS probe |
| `/root/ds115j/HANDOFF/FULL-MUST-AUDIT.md` | independent 11:22 UTC audit |
| `/root/ds115j/HANDOFF/MUST-1-4-VERIFICATION.md` | MUST-1 was FAIL until 2026-09-16 08:23; now historical |
| `/root/ds115j/HANDOFF/RECOVERY-RUNBOOK.md` | UART/TFTP/`sda2` rollback |
| `/root/ds115j/HANDOFF/HISTORY.md` | chronology |
| `/root/ds115j/HANDOFF/HELPER-TREE.md` | `/root/ds115j` + `/srv/tftp` inventory + hashes |
| `/root/ds115j/HANDOFF/PASTE-FOR-NEXT-AI.md` | self-contained kickoff prompt |
| `/root/ds115j/HANDOFF/project-context/` | copy of Cursor store |
| `/root/ds115j/HANDOFF/artifacts/ds115j.dts` | **synced 2026-09-16** with live DTS (no `alarm-gpios`) |
| `/root/ds115j/HANDOFF/artifacts/ds115j.dts.stale-with-alarm-gpios` | old HANDOFF copy (do not build from this) |
| `/root/ds115j/linux/arch/arm/boot/dts/marvell/ds115j.dts` | canonical board DTS SHA `89bc51c8…` |
| `/root/ds115j/qnap-poweroff-module/` | power-off module source |
| `/root/ds115j/backups/spi/` | canonical 8 MiB SPI dump |
| `/cursor/stores/bc-540055cf-bf32-4b50-a897-e75c83ae9097/` | original store (if still mounted) |

**Evidence precedence:** [`CURRENT-STATE.md`](CURRENT-STATE.md) beats older plans. [`permanent-boot.md`](project-context/docs/permanent-boot.md) / [`next-stage-boot.md`](project-context/docs/next-stage-boot.md) contain **stale `ide 0:1`** commands — chronology only.

## What already works (do not redo unless regressing)

- Local Debian boot from HDD (`ide 0:2`); helper/TFTP is recovery only.
- SATA rootfs, serial getty, SSH root/password, dbus, `reboot` via logind.
- RGMII Ethernet 1 Gbit/full, `.233` + DHCP, `networking.service` OK (cosmetic `Address already assigned`).
- SPI NOR dumped and hashed; MTD visible read-only.
- `sda3` `/srv/data`, SMART, chrony, zram lz4 2G, apt trixie + updates + security.
- Fan GPIO via `syno-fan.service` (**°C hysteresis**, idle ~1000 rpm, never pwm 0).
- MCU UART1: boot blink-blue + orange **steady** → ready blue/green + one short beep. Bay LED green = hardware; amber gpio-led stays **off**.
- `qnap_poweroff_ds115j` autoloads, binds `f1012100.poweroff`, **physical PSU cut proven**.
- DTB **no** `alarm-gpios`; udev idle.

## Ordered MUST work (status 2026-09-16)

Full text: [`MUST-FIXES.md`](MUST-FIXES.md).

| # | Item | Status |
|---|---|---|
| 1 | udev / gpio-fan `alarm-gpios` | **DONE** 08:23 UTC — live DTB has no alarm pin |
| 2 | DHCP + `.233` on `eth0:1` | **DONE** |
| 3 | data partition `sda3` `/srv/data` | **DONE** |
| 4 | SMART | **DONE** |
| 5 | NTP (chrony) | **DONE** |
| 6 | zram + journal caps | **DONE** |
| 7 | apt security/updates | **DONE** |
| 8 | samba + nftables | **SKIP** (owner) |
| 9 | recovery runbook + `deploy-boot.sh` | **DONE** — `list` + `dry-prev` live; `prev` not rebooted |
| 10 | cold boot health gate | **DONE** (~09:32 UTC historical) |
| 11 | MCU / LEDs / beep | **DONE** — Description matches orange **steady**; bay amber off (activity trigger tried + reverted) |
| 12 | fan vs SoC temp | **DONE** — °C hysteresis (not pwm-delta); overheat path unit-tested |

Still later (do not drop): independent backup/restore drill; burn-in before watchdog/UPS; optional real reboot of `deploy-boot.sh prev` **only with UART** (would boot the **alarm-gpios** `c1688fda…` kernel — do not do that casually).

## Kickoff (first 15 minutes)

1. SSH helper: `ls /root/ds115j/HANDOFF && cat /root/ds115j/HANDOFF/LANDMINES.md`.
2. SSH NAS **read-only**: `uname -a; ip -4 addr; systemctl --failed; systemctl is-active syno-fan.service syno-mcu-boot.service`.
3. Confirm UART is **free** on the Mac before any reboot.
4. Do **not** re-diagnose udev unless `uevent_seqnum` is climbing or `alarm-gpios` reappears.

## Constraints for this continuation

- Do not `saveenv`, `sf erase`/`write`, `bubt`, `fw_setenv`, write `/dev/mtd*`.
- Do not run `scripts/extract-hdd.sh` on the live NAS.
- Do not overwrite `/srv/tftp/uImage-ds115j` from `kernel/uImage-ds115j` (`69e60698…`) or from `uImage-ds115j.pre-alarm-gpios-c1688fda`.
- Current good TFTP **and** sda2 uImage: SHA-256 **`5ea71e0bc69a17ae269e278eedc28288702f1259edffefd97d420e01141ae3e8`**.
- Do not invent an I2C RTC. Never unbind `gpio-fan`. Fan pwm never 0.
- Keep root password unless owner says otherwise.

When you finish a change, record before/after, hashes, and whether it touched helper / `sda1` / `sda2` / U-Boot / SPI.
