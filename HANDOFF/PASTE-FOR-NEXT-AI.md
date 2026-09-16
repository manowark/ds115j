# PASTE-FOR-NEXT-AI — self-contained kickoff

Copy everything below the line into the next AI (Cursor/SSH session that can reach helper `.250` and NAS `.233`).

---

You are continuing an in-progress **Synology DS115j → Debian 13 (trixie armhf)** conversion. You are **not** starting from scratch. A complete handoff package is already on the helper.

**Обов’язково спочатку прочитай (read first):**

```text
/root/ds115j/HANDOFF/00-START-HERE.md
/root/ds115j/HANDOFF/LANDMINES.md
/root/ds115j/HANDOFF/CURRENT-STATE.md
/root/ds115j/HANDOFF/MUST-FIXES.md
/root/ds115j/HANDOFF/ACCESS.md
/root/ds115j/HANDOFF/MUST-1-4-VERIFICATION.md
```

Also: `HISTORY.md`, `HELPER-TREE.md`, `artifacts/MANIFEST.txt`, and `/root/ds115j/HANDOFF/project-context/` (especially `docs/ai-handoff-must-fixes.md`). If Cursor store is mounted: `/cursor/stores/bc-540055cf-bf32-4b50-a897-e75c83ae9097/`.

Helper hostname `rpi` = **192.168.68.250**. NAS hostname `ds115j` = **192.168.68.233**.
SSH: `ssh root@192.168.68.250` or `ssh root@192.168.68.233`, password **`ds115j`**. Helper pubkey auth remains enabled. Do not silently remove root/password.

## Proven facts (do not regress; later evidence wins)

- Hardware: Armada 370, **256 MiB RAM**, 1× WD Red ~2 TB (`WD20EFRX-68EUZN0`, S/N `WD-WCC4M1SAR61R`).
- Live OS: Debian 13.7, kernel `6.12.107+deb13-armmp`, cmdline `console=ttyS0,115200 earlyprintk root=LABEL=rootfs rootwait rw panic=10`.
- Disk: `sda1` 64G ext4 LABEL=rootfs UUID `fc9ea304-14d5-4494-a117-7dfda838e18b`; `sda2` 128M ext2 LABEL=boot UUID `eec9c4e3-7c83-40b6-af29-e28c4f228baa`; **`sda3` 1.8T ext4 LABEL=data UUID `2fd25b2a-ceb7-4155-bde9-87dec3d66e2b` mounted `/srv/data`**.
- **Permanent boot is `ext2load ide 0:2` ONLY. NEVER probe `ide 0:1` (U-Boot hangs). Never `scsi`.**
- PHY **88E1318S**, **`rgmii-id`**, NOT sgmii. MAC **`00:11:32:4d:c3:b8`**.
- UART from Mac: `screen /dev/cu.usbserial-BG01OOBA 115200`. Never leave another/root `screen` holding the port.
- Helper TFTP UDP **69** `/srv/tftp`; SPI TCP **45151**; HTTP **45152**.
- SPI 8 MiB dump SHA-256 **`cfbdc0dd57e3949957dbab23eb6befe84112fc36ed3b8a4e142c9ad78239dfc4`**. `saveenv` writes inside stock zImage — **do not saveenv/flash**.
- Power-off: module `qnap_poweroff_ds115j` exact vermagic; **physical PSU cut proven**; button recovers.
- Fan GPIO works (idle **1000**); `fan1_input` is not tach. Disk amber LED works. `rtc-mv` works. I2C0 empty — **do not invent an RTC**. Status LED MCU blink is **OK**.
- Current TFTP **and** sda2 `uImage-ds115j` SHA-256 **`5ea71e0bc69a17ae269e278eedc28288702f1259edffefd97d420e01141ae3e8`** (6060176 bytes). Previous alarm-gpios image `c1688fda…` is kept as TFTP `uImage-ds115j.pre-alarm-gpios-c1688fda` and sda2 `uImage-ds115j.pre-noalarm-20260916`. Stale helper `kernel/uImage-ds115j` is `69e60698…` — **do not overwrite current with stale**.
- HDD ramdisk SHA-256 **`dbbd30ec2c3772e2816eaa5e3295b0580a357fc93458dcb3bf063bf7bf65cd75`**.
- Module SHA-256 **`3354e4fb61ecb21afcdb09e80180e152d9b2a3313e97f1394db6cef79312b053`**.
- **MUST-2 config:** `/etc/network/interfaces` is DHCP on `eth0` plus `pre-up`/`post-up` `ip addr add 192.168.68.233/22 … label eth0:1 || true`. **Never restore `auto eth0:1 inet static`** (that caused `Address already assigned` and killed dhclient). Keep `.233` on **`eth0:1`**, never `:0`.
- **MUST-1 kernel fact:** live DTB has **no** gpio-fan `alarm-gpios` (deployed `5ea71e0b…`). Helper `linux/.../ds115j.dts` and HANDOFF `artifacts/ds115j.dts` match (SHA `89bc51c8…`). Do not unbind `gpio-fan` (it sets fan to 0).

## Live state after recheck (2026-09-16 08:26 UTC)

- NAS cold-booted twice this session: **08:05 UTC** (old kernel, proving cold-boot network/data) then **08:23 UTC** (new kernel after MUST-1 deploy). `systemctl --failed` empty both boots.
- **MUST-1 DONE:** new uImage deployed (`5ea71e0b…`, no gpio-fan `alarm-gpios`). DTB check `/sys/firmware/devicetree/base/gpio-fan/alarm-gpios` = **absent**. `uevent_seqnum` static (1778→1778/5 s); `systemd-udevd` 1 s CPU / 1.4 % (was 34.8 s in ~9 min); IRQ 44 = `mv64xxx_i2c` 0 irqs; `fan1_target`=1000.
- **MUST-2 DONE + cold boot proven:** `.233` on `eth0:1` + DHCP `.62` both boots. Interfaces file works. Benign `Address already assigned` messages from guarded pre-up/post-up `.233` add (`|| true`) — not the old fatal path; dhclient survives. Never restore `auto eth0:1`.
- **MUST-3 DONE + cold boot proven:** `sda3` `/srv/data` mounted rw,noatime.
- **MUST-4 DONE:** smartd, `smartctl -H PASSED`.
- **MUST-5 DONE:** chrony stratum 2, rtc-mv UTC, locale `en_US.utf8`.
- **MUST-6 DONE (~09:00 UTC):** `zram-tools` installed; `/dev/zram0` lz4 **2 GiB** prio 100; no HDD swap in fstab; journald capped (SystemMaxUse=50M). Owner requested the 2 GiB logical size.
- **MUST-7 DONE (~09:10 UTC):** `trixie` + `trixie-updates` + `trixie-security` in sources.list; `apt-get update` verified; 0 upgrades pending. No kernel packages in rootfs → apt cannot touch the running kernel. `unattended-upgrades` NOT installed.
- **MUST-9 DONE (~09:35 UTC):** operator runbook **`HANDOFF/RECOVERY-RUNBOOK.md`** + versioned deploy **`scripts/deploy-boot.sh`** (NAS `/root/deploy-boot.sh`; `deploy`/`prev`/`list`; `list` proved live on real `sda2` RO + hashes match TFTP). Full boot-image inventory in the runbook.
- **MUST-10 DONE (~09:32 UTC):** real cold power-cycle by owner — **all gate checks PASS** (no failed units, `.233`+DHCP, data mount, zram lz4 2G active at boot, udev idle + no alarm-gpios, SMART, module, chrony stratum 4, sda2 hashes == TFTP). **All MUST-1…10 closed.**
- **MUST-11 DONE (~09:55 UTC, beep re-verified ~10:20 UTC):** status LED / MCU control proven. PIC16LF1828 on UART1 at 9600 8N1 (`/dev/ttyS1`). Blue power LED `'4'/'5'/'6'` + status LED `'7'/'8'/'9'`/`':'`/`;'` confirmed visually by owner. **Beeper `'2'`/`'3'` also audible (both types distinct).** `/usr/local/sbin/syno-mcu.sh` (power/status/healthy/alarm/beep/ping) + boot sequence: `syno-mcu-boot-begin.service` (blink blue + steady orange during boot) → `syno-mcu-boot.service` (steady blue/green + **one short beep** once ready, gated After=network.target + readiness poll; owner-approved live). **dbus installed 2026-09-16 ~10:10** (was missing → `reboot/timedatectl/loginctl` bus errors; now auto-starts at boot, verified after 2 real reboots; `reboot` rc=0 via logind).
- **MUST-12 DONE (~11:31 UTC hysteresis fix; wait-loop re-proven on `reboot` 11:59 UTC):** SoC temp `hwmon0/temp1_input`; fan `hwmon1/pwm1` (25–255 ↔ ~1000–1900 RPM). **°C falling-edge hysteresis (2 °C)**, not pwm-delta (that hunted 110↔145 at 57–58 °C). `--self-test` covers hunt + ≥75 °C alarm latch. Service `After=udevd` + pwm wait/glob — **this boot** started 11:59:46, found hwmon 11:59:52. **Never unbind gpio-fan.** Never pwm 0.
- **Reboot verify 12:06 UTC (`HANDOFF/COLD-BOOT-VERIFY.md`): daily-ready YES.** Full `reboot` from HDD; SSH `.233`; all MUST-1…7,9,11,12 PASS. True PSU `poweroff` not automated (needs front button). MUST-10 historical PSU cut still stands.
- **Skip MUST-8** (samba/nftables per owner).
- **Still open:** independent backup/restore drill (ai-handoff MUST-7), burn-in before watchdog/UPS. `deploy-boot.sh prev` **dry-run only** — would restore alarm-gpios `c1688fda…`; do not reboot that without UART + intent.
- `qnap_poweroff_ds115j` loaded. Live DTB has **no** `alarm-gpios` (MUST-1 fixed).

## Landmines (again)

Never `ide 0:1`. Never wipe `sda1`/`sda2` (data is **`sda3` only**). Never `scripts/extract-hdd.sh` on the NAS. Never `ifdown eth0` from the only SSH session. Never restore SGMII DTS. Never `auto eth0:1`. Never unbind `gpio-fan`. Never `saveenv`/SPI write. Keep 256 MiB in mind (2 GiB **logical** zram is compressed in RAM; no Docker; no routine HDD swap). Kernel+DTB+HDD initramfs+poweroff `.ko` are one compatibility set. Fan target never 0. zram-tools: **omit `PERCENT`** in `/etc/default/zramswap` (if set, it forcibly overrides `SIZE`).

## Remaining MUST work order

MUST-1…7, 9–12 **DONE**. MUST-8 **SKIP**. Next: backup/restore drill; burn-in; do not casually `prev`+reboot onto `c1688fda…`.

## First actions

Read-only baseline on NAS + helper. One logical change at a time. If changing network, preserve `.233` and UART. Report exact command output.

**Не змінюй NAS-конфіг «на всяк випадок».** Record whether you touched helper, `sda1`, `sda2`, U-Boot, or SPI.

---
