# HISTORY — DS115j Debian conversion chronology

All dates **2026-09-15** unless noted. Helper `192.168.68.250`, NAS later `192.168.68.233`. Stock DSM originally booted from SPI.

Later proven facts **override** early docs. Permanent boot is **`ide 0:2`**. Power-off is **physically proven**. Ethernet is **RGMII**, not SGMII.

---

## 0. Goal and constraints

Owner wanted Debian on a DS115j instead of DSM. Device: Armada 370, 256 MiB, one HDD bay, SPI NOR MX25L6405D 8 MiB. UART always available from a Mac (`/dev/cu.usbserial-BG01OOBA`). A Raspberry Pi helper provides TFTP, HTTP, and a build tree under `/root/ds115j`.

Doozan/deelan (2021) ported DS213j almost 1:1, including **`sgmii`** — that was **wrong for DS115j** (U-Boot already said `RGMII0 Phy`; DSM PHY ID `1410e90` = 88E1318S). That article is why Ethernet was the first hard bug.

DSM is **not** a required recovery target. SPI dump is anti-brick, not a mandate to restore DSM.

---

## 1. Stock extraction and TFTP skeleton

- Extracted stock kernel artifacts (`stock-kernel.bin`, `zImage`, `vmlinux.raw`, binwalk tree).
- Built a legacy U-Boot `uImage` from Debian `6.12.107+deb13-armmp` zImage + custom appended DTB.
- Minimal BusyBox initramfs; static TFTP boot (`ipaddr .233`, `serverip .250`).
- Nested mainline tree `/root/ds115j/linux` used for `dtc` only (HEAD `587858367-dirty`); **not** the running kernel source.

---

## 2. Initramfs networking repair

BusyBox ramdisk could not talk on Ethernet until:

- `marvell.ko` + module metadata + `/sbin/modprobe`
- BusyBox `ip` / `ping` links
- init loaded PHY driver **before** `mvmdio`/`mvneta`, assigned `.233/22`, pinged helper

Evidence: `project-context/internal/initramfs-fix.md`.

---

## 3. Ethernet root cause: SGMII → RGMII-ID

Under copied DS213j `sgmii`:

- PHY carrier could look up
- Helper tcpdump: ARP from helper, **no NAS frames**
- Linux: TX FIFO timeout

Fix: DTS `phy-mode = "rgmii-id"` + `ge0_rgmii_pins`. Live: 1000/full, ping gateway/helper, RX/TX errors 0.

Evidence: `internal/rgmii-ab-test.md`, `internal/rgmii-helper-tcpdump.md`, `internal/helper-tcpdump.md`.

**Do not revert to SGMII.** Backup images `*.bak-sgmii*` exist only as history.

---

## 4. Peripheral DTS expansion

Added UART1 / `synology,power-off`, disk amber LED (MPP31), `gpio-fan` (MPP65/64/63, alarm MPP38), I2C0, read-only SPI NOR partitions (`jedec,spi-nor`, Macronix MX25L6405D — not Micron n25q064).

Later I2C pinctrl (MPP2/MPP3) was required; without it the bus was wrong. Scan still empty. Speculative `isl12057@0x68` was added then **removed**.

Evidence: `docs/dts-peripherals.md`, `docs/peripherals-status.md`.

---

## 5. SPI dump (before any `saveenv`)

Full 8 MiB + separate 64 KiB vendor region captured via Linux MTD and helper TCP 45151 / harvest scripts.

```text
SPI 8 MiB SHA-256  cfbdc0dd57e3949957dbab23eb6befe84112fc36ed3b8a4e142c9ad78239dfc4
vendor 64 KiB      9cc6345f4a694d492b6aa4142198bf389d2ebfd63bbe964b09d2e70dd635daad
```

Stock env in dump: `bootcmd=sf probe 0 50000000;bootm 0xf40c0000 0xf4390000`.  
**`saveenv` writes at 1 MiB into the chip, inside zImage.** Dump exists; SPI writes remain high risk.

---

## 6. Debian HDD root (trixie armhf)

- debootstrap-style rootfs on helper → `rootfs-trixie-armhf.tar.gz` (134,385,614 bytes).
- HDD initramfs: `sata_mv`/`sd_mod`/ext4/`blkid`, `LABEL=rootfs`, `switch_root`.
- Partitioned **sda1 64G rootfs** + later **sda2 128M boot**; **~1.75T left free**.
- Fixed locked root (`root:*` → real shadow), `serial-getty@ttyS0`, OpenSSH main config + host keys, MAC pin `00:11:32:4d:c3:b8`.
- Temporary password **`ds115j`** — **owner wants it kept** on LAN.

`scripts/extract-hdd.sh` is **destructive**. Do not rerun.

Evidence: `docs/hdd-boot-fix.md`, `internal/hdd-boot-sync.md`.

---

## 7. Permanent local boot (`ide 0:2`)

U-Boot cannot reliably use `ide 0:1` — **hang**. Dedicated ext2 `sda2` became the boot source:

```text
ext2load ide 0:2 0x01000000 /boot/uImage-ds115j
ext2load ide 0:2 0x02000000 /boot/uRamdisk-hdd-ds115j
bootm 0x01000000 0x02000000
```

Normal boot **no longer depends on TFTP**. Helper remains recovery.

Older markdown still says `ide 0:1` / TFTP `bootcmd` — **stale**.

Evidence: `docs/permanent-boot.md` (mixed current/historical), `docs/usable-system-gaps.md`.

---

## 8. I2C + RTC reality

After pinctrl, `i2cdetect` empty; probes at `0x30`/`0x32`/`0x68` NACK.  
Working clock: SoC **`rtc-mv`**. Unbound fake RTC node removed from DTB. TFTP still has `uImage-ds115j.with-unbound-rtc68-20260915` as a **do-not-boot-primary** historical image.

---

## 9. Power-off module

Debian kernel has `# CONFIG_POWER_RESET_QNAP is not set`. Built out-of-tree GPL module against **exact** headers/vermagic:

```text
/root/ds115j/qnap-poweroff-module/qnap-poweroff-ds115j.c
vermagic 6.12.107+deb13-armmp SMP mod_unload modversions ARMv7 p2v8
SHA-256 3354e4fb61ecb21afcdb09e80180e152d9b2a3313e97f1394db6cef79312b053
```

Sends Synology UART command `'1'` at 9600 baud on UART1. Autoloads, binds `f1012100.poweroff`.

**Physical test:** `poweroff` **cuts PSU**; front button restores power/boot. Docs that say “dry-check only” are superseded.

DTB/uImage rebuilt as `Debian 6.12.107 DS115j I2C` (6,060,232 bytes, SHA `c1688fda…`). Deployed to TFTP, `sda2`, and `sda1 /boot`.

Evidence: `docs/poweroff-i2c-plan.md`, `internal/poweroff-i2c-result.md`.

---

## 10. DHCP + static `.233`

Installed `isc-dhcp-client`. `eth0` dhcp + `eth0:1` `192.168.68.233/22`. Exit hook re-adds `.233` after dhclient flush. DNS supersede `.1` and `1.1.1.1`.

**Same-day proof:** both `.233` and DHCP `.62` worked; dhclient running.

**Later live assessment + this handoff probe:** `networking.service` failed (`Address already assigned` on `eth0:1` because `pre-up` already added it). By 19:50 UTC lease expired, **no dhclient**, **only `.233`**. MUST-2 remains.

Evidence: `docs/network-dhcp-static.md`, `internal/network-dhcp-static-result.md`.

---

## 11. Peripherals status (live)

| Subsystem | Result |
|---|---|
| Fan | 1000/1500/1900 GPIO map works; restored 1000 |
| Disk amber LED | sysfs on/off works |
| SoC thermal | ~65–70 °C under load |
| USB | two EHCI hubs + usb-storage; no stick soak test |
| Watchdog | `orion_wdt` + `/dev/watchdog0`; not armed |
| Status LED / beeper | MCU; optional; blink OK |
| I2C RTC | none |

---

## 12. Readiness / gaps / handoff docs

- `docs/readiness-assessment.md` — Doozan comparison (partially stale: written when TFTP/BusyBox was current).
- `docs/usable-system-gaps.md` — latest daily-NAS gap analysis (Ukrainian). SSH-hardening advice there **conflicts with owner preference** (keep root password).
- `docs/ai-handoff-must-fixes.md` — canonical MUST-1…10 + access cheat sheet.
- `docs/ds115j-helper-inventory.md` — helper file map.

This `/root/ds115j/HANDOFF/` package (2026-09-15 ~22:50 local helper) copies the store, binaries, and a new live probe so another AI with SSH to `.233` and `.250` can continue without Cursor memory.

---

## 13. MUST-5 NTP / chrony (2026-09-15 21:10 UTC)

Prior agent installed locale + chrony then stopped before documenting RTC. This turn:

- Confirmed `chrony` enabled/active; Debian pool + `rtcsync` + DHCP `sourcedir`; timesyncd absent.
- Installed `util-linux-extra` for `hwclock`; `hwclock -w --utc`; RTC readback sane.
- Did **not** start zram or apt-security.

---

## 15. MUST-1..4 verification (21:54 UTC)

SSH from helper. See [`MUST-1-4-VERIFICATION.md`](MUST-1-4-VERIFICATION.md).

- **MUST-1 FAIL:** gpio-fan alarm still ~10 hwmon CHANGE/s; udev cannot drop on systemd 257; live DTB still has `alarm-gpios`. Started `networking.service` without `ifdown`. Replaced split GOTO udev rules with `nowatch` comments.
- **MUST-2 PASS live:** `.233` + DHCP `.62` + dhclient; interfaces already idempotent.
- **MUST-3 PASS:** `sda3` `/srv/data`.
- **MUST-4 PASS:** smartd + PASSED.
- MUST-5 still OK. MUST-8 skipped per owner. Next: MUST-1 DTB deploy and/or MUST-6 zram.

---

## 16. MUST-1 deploy + cold-boot proofs (2026-09-16 08:05–08:26 UTC)

New day. A cold boot at **08:05 UTC** (old kernel still) already proved MUST-2/3 at boot: `.233` + DHCP `.62`, `sda3` mounted, `systemctl --failed` empty — but udev still spun (seqnum ~100/s).

**Found undocumented:** `/root/ds115j/artifacts/uImage-ds115j.new-noalarm` (SHA `5ea71e0b…`, 6,060,176 B) built 2026-09-15 23:27, not in any doc. Read-only verified: zImage identical (`b508abca…`), DTB differs only by gpio-fan `alarm-gpios` removal. HANDOFF `artifacts/ds115j.dts` is stale (still has `alarm-gpios`); live helper DTS is the fixed one (`89bc51c8…`).

**Deploy:**
- Copied to `/srv/tftp/uImage-ds115j.new-noalarm` + `HANDOFF/artifacts/noalarm/`.
- `sda2:/boot/uImage-ds115j` ← new; previous kept as `uImage-ds115j.pre-noalarm-20260916` (`c1688fda…`); also updated `sda1:/boot` (informational).
- Root `screen`/UART kept free; reboot via SSH at 08:22 → clean boot 08:23.

**MUST-1 PASS:** live DTB has no `alarm-gpios`; `uevent_seqnum` static (1778→1778/5s); udev 1 s CPU / 1.4 %; IRQ 44 = `mv64xxx_i2c` 0 irqs; fan 1000; no failed units; network/data/SMART/chrony all OK same boot.

TFTP `uImage-ds115j` left as `c1688fda…` until the recovery runbook (MUST-9) is written.

---

## 17. MUST-6 zram + journal bounds (2026-09-16 ~09:00 UTC)

- Installed `zram-tools` 0.3.7-1 (Debian trixie has no Debian `zramswap` package) → `zramswap.service` enabled.
- Config `PERCENT` nuance: the init script **overrides SIZE whenever PERCENT is set** (even `PERCENT=0` gives ~50 % fallback) — fix was to **omit** `PERCENT` entirely. `/etc/default/zramswap`: `ALGO=lz4`, `SIZE=2048`, `PRIORITY=100`.
- Live: `/dev/zram0` lz4, **2 GiB logical**, 0 B used, prio 100; `fstab` has no swap (no HDD swap). `systemctl is-active zramswap` = **active**.
- `/etc/systemd/journald.conf`: `SystemMaxUse=50M`, `RuntimeMaxUse=50M`, `Compress=yes`, `MaxRetentionSec=30day`; journald restarted; current usage 45.6M.
- Owner explicitly requested **2 GiB** logical zram size (accepted as configured).

---

## 18. MUST-7 apt security suites (2026-09-16 ~09:10 UTC)

- `sources.list` already minimal (`trixie main`). Added, matching existing style via deb.debian.org:
  `trixie-updates main`, `debian-security trixie-security main`.
- `apt-get update`: both new InRelease files fetched + verified.
- `apt-get upgrade --dry-run`: **0 upgraded** (rootfs current as installed).
- Rootfs has **no linux-image/headers packages** (`dpkg -l`), so the booted kernel (custom `sda2` uImage) cannot be changed by apt. `unattended-upgrades` kept **uninstalled** (minimal 256 MiB policy). No holds needed.

---

## 19. MUST-9 recovery runbook + boot deploy (2026-09-16 ~09:35 UTC)

- Wrote operator runbook **RECOVERY-RUNBOOK.md** (HANDOFF): scenarios A (SSH lost, keep `.233`, avoid `ifdown eth0`), B (U-Boot rollback via `sda2` known-good images, then TFTP), C (corrupt `sda2` → recovery ramdisk + e2fsck), D (helper down), E (automated deploy), F (post-recovery checklist); full boot-image inventory with 16-char sha256; UART guidance; explicit **never `ide 0:1`/SPI-write-first**.
- Wrote **scripts/deploy-boot.sh** (canonical on helper; installed on NAS as `/root/deploy-boot.sh`): versioned bundle deploy (`deploy`), device-local rollback (`prev`), read-only inventory (`list` → mounts `sda2` `-o ro`). Bundle = `uImage-ds115j` + `uRamdisk-hdd-ds115j` + `MANIFEST`; current pair rotated to `*.pre-<STAMP>`, keeps newest 3; read-back sha256 verified **before** umount; `sync` then umount-on-exit. Never touches sda1/sda3/SPI/U-Boot env.
- **Proof (no `ide 0:1`, no SPI write):** ran `/root/deploy-boot.sh /nonexistent list` on NAS — read-only mount showed current `uImage-ds115j` `5ea71e0b…`, `uImage-ds115j.pre-noalarm-20260916` `c1688fda…`, `uImage-ds115j.pre-poweroff-i2c-20260915` `69e60698…`, `uRamdisk-hdd-ds115j` `dbbd30ec…` — all identical to helper TFTP hashes. Actual boot of a previous image deferred (would need an opportunistic reboot; MUST-10).
- Touched: helper (docs + script), NAS `/root/deploy-boot.sh` (rootfs home only). Not touched: sda1/sda2/U-Boot/SPI.

---

## 20. MUST-10 cold-boot verification (2026-09-16 ~09:29–09:32 UTC)

- Owner physically power-cycled NAS: `.233` went DOWN (~24 s), then back UP. Operator poller proved real cold boot.
- Fresh boot: **kernel 12.878 s, userspace 36.997 s, `graphical.target` 49.875 s**; uptime 1 min at gate.
- Gate **all PASS**: no failed units; `.233` static + DHCP `.62` + default route; `/srv/data` (`sda3`) rw,noatime mounted; **zram `lz4` 2 GiB prio 100 active at cold boot** (256K used); SMART WD Red WD20EFRX-68EUZN0 enabled; udev `uevent_seqnum` static 1798→1798/5s + no udev CPU + live DTB **no** `alarm-gpios` (MUST-1 regression green); `qnap_poweroff_ds115j` loaded; chrony active stratum 4 (cloudflare), leap Normal, ~2 ms offset, RTC UTC matches; sda2 re-`list`ed — `5ea71e0b…` / `c1688fda…` / `69e60698…` all match helper TFTP.
- Memory 233 MiB total / 166 MiB available. Loadavg settling.
- **All MUST-1…10 closed.** Touched: none on top of prior items (verification only). Watchdog stays disarmed until anti-loop test; UPS/front-button burn-in still open.

---

## 21. MUST-11 status LED / MCU control (2026-09-16 ~09:50–09:55 UTC)

- Owner requested **status LED/MCU** as MUST-11. Blue power button LED was blinking continuously (DSM-absent MCU default) — prompts to reverse-engineer protocol.
- Confirmed mainline-documented Synology **PIC16F1828** single-byte command set (9600 8N1) via `ttyS1` (`/dev/ttyS1` exists, root:dialout). `/dev/ttyS1` termios verified.
- **Live owner-verified commands (2026-09-16):**
  - Blue power LED: `'4'` steady, `'5'` blink, `'6'` off — owner confirmed all three states.
  - Status LED: `'7'` off, `'8'` green steady, `'9'` green blink, `':'` orange steady, `';'` orange blink — owner confirmed.
  - Beep `'2'`/`'3'` — MCU-supported; first single quiet short beep was missed; **explicit retest (3 long + 4 short) confirmed audible, both types distinct** (buzzer present and working; no HW change needed).
  - Did **not** send `'1'` (power-off) / `'C'` (reset) — kernel/module contract unchanged.
- Delivered:
  - **`/usr/local/sbin/syno-mcu.sh`** — userland driver: `power on|blink|off`, `status off|green|green-blink|orange|orange-blink`, `healthy` (`'4'`+`'8'`), `alarm` (orange-blink + 3 long beeps, verified live), `beep short|long`, `ping`. Transient open/write/close per command → race-free vs kernel power-off handler.
  - **`syno-mcu-boot.service`** (oneshot, RemainAfterExit=yes, `WantedBy=multi-user.target`) — enabled + started; applies healthy state at every boot.
  - Canonical helper copy: `/root/ds115j/scripts/syno-mcu.sh` + `syno-mcu-boot.service`.
- Verification: service `active`, journal clean (`0x34`/`0x38` sent), owner confirmed both LEDs steady after `healthy`.
- Touched: NAS rootfs only (`/usr/local/sbin`, `/etc/systemd/system`). Not touched: helper docs synced after; sda1/sda2/U-Boot/SPI untouched. All MUST-1…11 now **closed**.

---

## §22 Reboot test + dbus (~10:06–10:14 UTC 2026-09-16)

- Two real reboots via `reboot`; full boot gate passed both times: 0 failed units, `.233`+DHCP, sda3 rw, zram lz4 2G active, `qnap_poweroff_ds115j` loaded, `syno-mcu-boot.service` sent `0x34`+`0x38` at boot (LED healthy state applied automatically, journal-verified).
- **Discovery:** `dbus` was NOT installed → util-linux `reboot`, `timedatectl`, `loginctl` failed with "Failed to connect to system scope bus via local transport". First `reboot` still worked only via syscall fallback.
- **Fix (owner-approved):** installed `dbus` 1.16.2-2 (`--no-install-recommends`); unit is `static`, so enabled via symlink `dbus.service → /etc/systemd/system/multi-user.target.wants/`. Now auto-starts at boot; `timedatectl` reports "System clock synchronized: yes"; `reboot` exits rc=0 via logind.
- Verified persistence across a real reboot (dbus active + socket present at boot).
- Touched: NAS rootfs (`/etc/systemd/system/multi-user.target.wants/dbus.service`, daemon-reload). sda1/sda2/U-Boot/SPI untouched.

---

## §23 Boot indication + ready-beep (2026-09-16, owner-approved)

- Owner requested: boot indication on LEDs, and beep once boot finishes.
- **Design (final):** `syno-mcu-boot-begin.service` (`WantedBy=systemd-udevd-kernel.socket`, runs ~4 s in) → power LED **blinks** + status LED **orange steady**; `syno-mcu-boot.service` (ordered `After=network.target networking.service begin`, plus readiness poll: route + `/srv/data` + zram, 120 s fail-open-to-orange) → power/status **steady** + **one short beep**.
- Iterations: v1 beep double short→single (owner); v1 begin `After=udevd.service` (delayed, useless window) → socket-want trick; v2 began **and** ready fired concurrently (no gate) → added `After=network.target` + readiness poll; v3 orange blink→**steady** during boot (owner).
- Live demo boot: blink window `10:36:21→10:36:52` (~31 s), green+beep exactly when network came up; 0 failed units. Owner confirmed "Все так".
- Touched: NAS `/usr/local/sbin/syno-mcu-boot.sh`, `/etc/systemd/system/syno-mcu-boot{,-begin}.service`; helper copies updated. sda1/sda2/U-Boot/SPI untouched.

## §24 MUST-12 — balanced fan control (2026-09-16 ~10:55 UTC)

- Owner: "MUST-12 - Fan за температурою" — fan speed should follow SoC temperature.
- Discovered: gpio-fan at fixed 1000 RPM; SoC idle ~62°C. Control knobs: `hwmon1/pwm1` (0–255 ↔ 1000–1900 RPM), `hwmon0/temp1_input` (millidegrees).
- Audible sweep (owner-confirmed): pwm 20–30→1000, 100→1350, 120→1500, 200→1750, 255→1900 RPM.
- Owner chose **balanced** curve; implemented `/usr/local/sbin/syno-fan.sh` (daemon, 20 s poll, pwm delta≥15 hysteresis, balanced temp→pwm table, sensor-missing fallback pwm=65) + `syno-fan.service` (Type=simple, WantedBy=multi-user, enabled).
- Integrated overheat → `syno-mcu.sh alarm` (orange-blink + 3 long beeps) once per ≥75°C episode, clears ≤70°C.
- Verified live: service logged `63°C → pwm=190` and tracks temp. Helper copies updated. sda1/sda2/U-Boot/SPI untouched.

## §25 MUST-12 hysteresis + TFTP default + docs (2026-09-16 ~11:31 UTC)

- FULL-MUST-AUDIT: fan hunted 110↔145 at 57–58 °C because hysteresis compared **pwm** bands.
- Replaced with **2 °C falling-edge** hysteresis; min pwm 25; `syno-fan.sh --self-test` PASS (hunt + ≥75 °C latch, no thermal stress).
- `syno-fan.service`: `After=systemd-udevd.service systemd-modules-load.service`; script waits/globs pwm1.
- Live after restart: `62°C → pwm=145 fan1_target=1500`; samples at 58.8 °C **stayed 145/1500** (old logic would have dropped to 110).
- TFTP default `/srv/tftp/uImage-ds115j`: `c1688fda…` → `5ea71e0b…`; old kept as `uImage-ds115j.pre-alarm-gpios-c1688fda`.
- `deploy-boot.sh list` / `dry-prev` (no write). `prev` would restore alarm-gpios kernel; not rebooted.
- MUST-11: unit Description orange **steady**; disk amber trigger `disk-activity` (**reverted in §26**).
- HANDOFF `artifacts/ds115j.dts` synced to live DTS; stale copy renamed.
- Touched: helper scripts/docs/TFTP; NAS `/usr/local/sbin/syno-fan.sh`, units, udev rule, `/root/deploy-boot.sh`. sda2/U-Boot/SPI **not** rewritten.

## §26 Bay LED revert — amber activity trigger removed (2026-09-16 ~12:2x UTC)

- Owner report: “HDD blinks orange; status blinks orange during boot.” Intent: **status solid orange while booting, HDD green**.
- Root cause of the orange HDD blink: **§25’s own change**. The bay LED is **bi-color**; only the **amber** half is a Linux gpio-led (`synology:amber:disk`, MPP31, `gpio0 31 GPIO_ACTIVE_LOW`). The **green** half is driven by the SATA link in **hardware** and never appears in `/sys/class/leds` (`/sys/kernel/debug/gpio` shows exactly one claimed line). Attaching `disk-activity` to amber lit/blinked amber on every I/O and masked green.
- Fix: removed `/etc/udev/rules.d/60-ds115j-disk-led.rules`, `udevadm control --reload-rules`, `trigger=none`, `brightness=0`. Verified `[none]` + `0`. Helper copy kept **uninstalled** as `scripts/disk-led-amber-activity.rules.optional-NOT-INSTALLED` with an explanatory header.
- Status-LED blink during boot is **not** ours: journal this boot shows `syno-mcu-boot-begin` sending `':'` (**orange steady**, 0x3A) at 11:59:35 and `syno-mcu-boot` sending `'8'` + beep at 12:00:06. The blink the owner sees is the **MCU power-on default** during U-Boot + kernel + ~4 s userspace (`/dev/ttyS1` does not exist earlier). Removing it would require U-Boot env writes → **forbidden**.
- Touched: NAS `/etc/udev/rules.d/` + LED sysfs; helper script rename + docs. sda1/sda2/U-Boot/SPI untouched.

## Preferences recap (owner)

- Keep root/password SSH on LAN.
- Status LED optional; MCU blink OK.
- DSM restore not required.
- 256 MiB: zram not HDD swap; no Docker/heavy media stacks.
