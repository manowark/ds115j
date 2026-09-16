# LANDMINES — do not do these

Violating any of these can brick boot, hang U-Boot, or destroy the only disk.

## 1. Never `ide 0:1`

This board’s U-Boot **hangs** on `ide 0:1` (including `ext2ls` / `ext2load`).

Use **only `ide 0:2`** (the 128 MiB ext2 `LABEL=boot` partition).

Older docs (`permanent-boot.md`, `next-stage-boot.md`, some internals) still show `ide 0:1`. Treat those lines as **historical**, not commands.

Do not run **`scsi`** commands. This U-Boot is **`ide`**.

## 2. Never casual `saveenv` / SPI write

Synology U-Boot stores env at SPI offset **`0x00100000`**, which sits **inside the stock zImage** partition.

- Do not `saveenv` unless you are executing a separately reviewed procedure with UART + verified dump.
- Do not `sf erase`, `sf write`, `bubt`, `fw_setenv`, or write `/dev/mtd*`.
- A verified 8 MiB dump exists; that does **not** make SPI writes routine.

Dump (do not overwrite):

```text
/root/ds115j/backups/spi/ds115j-spi-8m-20260915-124830.bin
SHA-256 cfbdc0dd57e3949957dbab23eb6befe84112fc36ed3b8a4e142c9ad78239dfc4
HANDOFF copy: /root/ds115j/HANDOFF/artifacts/spi/
```

## 3. Do not wipe or move `sda1` / `sda2`

- `sda1` = Debian root (`LABEL=rootfs`).
- `sda2` = **U-Boot boot files**. Moving/reformatting/renumbering it unboots the NAS.
- `scripts/extract-hdd.sh` **destroys `/dev/sda`**. Never run it on the live NAS.
- New data volume must use **unallocated** space only.

Linux `/boot` on `sda1` is **not** what U-Boot reads. U-Boot reads **`sda2:/boot`**.

## 4. Status LED MCU — proven protocol, race-free use

The front status LED (green/orange) and blue power LED are driven by the **PIC16LF1828 on UART1** (`/dev/ttyS1`, 9600 8N1).

**Proven commands** (owner-confirmed 2026-09-16): `'4'/'5'/'6'` = blue power LED steady/blink/off; `'7'/'8'/'9'` = status LED off/green steady/green blink; `':'`/`';'` = status LED orange steady/blink; `'2'/'3'` = short/long **beeps (audible, both types distinct)**.

Driver: **`/usr/local/sbin/syno-mcu.sh`**. Boot sequence: `syno-mcu-boot-begin.service` (blink blue + steady orange, booted via `systemd-udevd-kernel.socket` wants) then `syno-mcu-boot.service` (steady blue/green + **one short beep** once network + data + zram are up; ordered After network.target + readiness poll). Alarm pattern: `syno-mcu.sh alarm` (orange-blink + 3 long beeps). Each command opens/closes the port transiently — nothing holds UART1 at power-off.

> **dbus (2026-09-16):** was missing → `reboot`/`timedatectl`/`loginctl` failed with "Failed to connect to system scope bus". Installed `dbus` 1.16.2-2; enabled at boot via symlink `multi-user.target.wants/dbus.service`. If a fresh install ever drops this again, re-add the symlink + `systemctl daemon-reload`.

**Do NOT send `'1'`** (power-off; kernel module `synology,power-off` handles it) or `'C'` (hard reset) manually. `'A'`/`'B'` (D8 MB LED) not present on DS115j.

**Bay/HDD LED is bi-color and only half of it is yours.** `synology:amber:disk` (MPP31) is the **amber** half; the **green** half is wired to SATA in hardware. Do **not** attach `disk-activity` (or any activity trigger) to the amber LED — the bay LED then blinks **orange** and hides the normal green. Owner wants the bay LED **green**; keep amber `trigger=none`, `brightness=0` and reserve it for faults. Tried and reverted 2026-09-16.

## 5. Fan control — temperature-based (never unbind)

The fan is a **gpio-fan** on `/sys/class/hwmon/hwmon1`. Controller: **`/usr/local/sbin/syno-fan.sh`** (daemon) + `syno-fan.service` (enabled). Reads SoC temp from `hwmon0/temp1_input` (millidegrees) and writes `hwmon1/pwm1` (25–255 ↔ ~1000–1900 RPM) with a balanced curve and **2 °C falling-edge hysteresis** (20 s poll). `syno-fan.sh --self-test` covers hunt + overheat latch without heating the box.

- **Never unbind `gpio-fan`** and never write to `pwm1_enable`/`pwm1_mode`.
- Manual control: `echo <pwm> > /sys/class/hwmon/hwmon1/pwm1` (pwm ≥ 25). Use `syno-mcu.sh alarm` for overheat signalling, not raw bytes.
- Overheat: `syno-fan.sh` auto-triggers `syno-mcu.sh alarm` at ≥75°C, once per episode; clears ≤70°C.

## 6. Keep the root password (owner preference)

Root password SSH on this **trusted LAN** is an accepted preference.

- Do not silently switch to key-only or delete root login.
- Do not expose SSH to the Internet.
- `usable-system-gaps.md` argues for locking SSH down; **ai-handoff / owner preference overrides that** unless the owner changes their mind.

## 6. 256 MiB RAM is a hard ceiling

- Available RAM ~233 MiB; **no swap** as of the 2026-09-15 probe.
- Use **modest zram**, not a large HDD swap file as default.
- Do not install Docker/K8s, Plex transcoding, Nextcloud “full stack”, etc.
- `systemd-udevd` spinning already burns a large fraction of the single 800 MHz core — fix that before adding Samba load.

## Other landmines

- **SGMII DTS is wrong.** Do not restore `phy-mode = "sgmii"` or boot `*.bak-sgmii*` images.
- **No external I2C RTC.** Bus scan empty; `0x30`/`0x32`/`0x68` NACK. Do not add `isl12057@0x68`. `rtc-mv` is the real clock.
- **Do not `ifdown eth0`** or blindly `systemctl restart networking` from the only SSH session. Preserve `.233`; keep UART as rollback.
- **Do not overwrite TFTP/current `uImage` from stale copies.**  
  Current TFTP **and** sda2: SHA-256 `5ea71e0bc69a17ae269e278eedc28288702f1259edffefd97d420e01141ae3e8` (6,060,176 bytes).  
  Previous TFTP default (alarm-gpios), kept: `/srv/tftp/uImage-ds115j.pre-alarm-gpios-c1688fda` = `c1688fda25f1472d4b7b5b65b5ecc2a4d7b8a780cd9d6bb26c7c7df92d1c6a23`.  
  Older `kernel/uImage-ds115j` / `69e60698…` (6,060,240 bytes) — **do not promote**.
- **Kernel + appended DTB + HDD initramfs + `qnap-poweroff-ds115j.ko` are one set.** Exact vermagic `6.12.107+deb13-armmp`. Do not APT-upgrade the kernel as a normal package update.
- **Fan:** never leave target at 0; restore **1000**. `fan1_input` is **not** measured RPM.
- **UART:** do not leave `screen` holding `/dev/cu.usbserial-BG01OOBA`.
- **Do not boot `uImage-nodtb`.**
