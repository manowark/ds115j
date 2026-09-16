# MUST-FIXES — remaining work

Source of truth for numbering: `project-context/docs/ai-handoff-must-fixes.md`.

The parent kickoff also asked for this **execution order** (udev → network → data → SMART → NTP → zram → apt → samba+nftables → recovery runbook → verify). Follow that order on the live box. Mapping to ai-handoff IDs is noted on each item.

Live verification **2026-09-15 21:54 UTC**: [`MUST-1-4-VERIFICATION.md`](MUST-1-4-VERIFICATION.md), [`CURRENT-STATE.md`](CURRENT-STATE.md).
**MUST-1 fixed 2026-09-16 08:23 UTC** (see below). MUST-2/3/4/5 **done**. MUST-6 **done 2026-09-16 ~09:00 UTC** (see below). MUST-7 **done 2026-09-16 ~09:10 UTC** (see below). MUST-8 **skipped** per owner. MUST-9 **done 2026-09-16 ~09:35 UTC** (recovery runbook + versioned boot deploy; see below). MUST-10 **done 2026-09-16 ~09:32 UTC** (real cold power-cycle PASS; see below). MUST-11 **done 2026-09-16 ~09:55 UTC** (status LED/MCU proven; disk amber `disk-activity` 11:31 UTC). MUST-12 **done 2026-09-16 ~11:31 UTC** (balanced fan + **°C hysteresis**; pwm-delta hunting closed). Remaining: independent backup/restore drill, burn-in before watchdog/UPS.

---

## MUST-1 — eliminate `systemd-udevd` CPU spin — **DONE 2026-09-16 08:23 UTC**  
**Work-order #1 · ai-handoff MUST-1**

**Root cause (proven):** gpio-fan `alarm-gpios` (MPP38) in the **running** DTB. Driver requests `IRQ_TYPE_EDGE_BOTH`, handler returns `IRQ_NONE`, workqueue emits hwmon `KOBJ_CHANGE` ~10/s. Continues with udevd **stopped**. IRQ 44 hits 100000 then gpio line shows IRQ disabled; **uevents keep going**.

**udev cannot fix this on systemd 257:** `ignore_device` / `last_rule` removed; GOTO LABEL is per-file. Split `01-gpio-fan.rules` + `99-zzzz-end.rules` was a no-op. Current NAS rule is `nowatch` + comments only.

**The fix was already built, undocumented:** `uImage-ds115j.new-noalarm` (SHA-256 `5ea71e0bc69a17ae269e278eedc28288702f1259edffefd97d420e01141ae3e8`, 6,060,176 B) in `/root/ds115j/artifacts/`, built 2026-09-15 23:27 after the 22:02 snapshot. Verified read-only before use: **same zImage** payload (`b508abca…`) as previous; DTB differs only by gpio-fan `alarm-gpios` removal (+ phandle renumber). HANDOFF `artifacts/ds115j.dts` was stale until 2026-09-16 11:31 UTC; it now matches live helper DTS `linux/…/marvell/ds115j.dts` (SHA `89bc51c8…`, no `alarm-gpios`). Old copy: `artifacts/ds115j.dts.stale-with-alarm-gpios`.

**Deploy (2026-09-16):**
- `sda2:/boot/uImage-ds115j` → new (keep previous as `uImage-ds115j.pre-noalarm-20260916` = `c1688fda…`; `uImage-ds115j.pre-poweroff-i2c-20260915` = `69e60698…` still present).
- `sda1:/boot/uImage-ds115j` (informational; U-Boot reads only `sda2`).
- `/srv/tftp/uImage-ds115j.new-noalarm` added (helper). **2026-09-16 11:31 UTC:** TFTP default `/srv/tftp/uImage-ds115j` promoted to `5ea71e0b…` (same as sda2). Previous default kept as `/srv/tftp/uImage-ds115j.pre-alarm-gpios-c1688fda` and `uImage-ds115j.pre-noalarm-20260916`.
- No U-Boot/SPI change. SSH reboot. Existing `/etc/udev/rules.d/01-gpio-fan.rules` left as-is (comments+`nowatch`; harmless, can be removed later).

**Do not** unbind `gpio-fan` (sets fan to 0). No DT overlay configfs on the NAS.

**Accept (met 08:24–08:26 UTC):** live DTB `alarm-gpios` absent; `uevent_seqnum` static 1778→1778 over 5 s (was ~10–100/s); `systemd-udevd` 1 s CPU / 1.4 % (was 34.8 s in ~9 min); IRQ 44 = `mv64xxx_i2c` 0 irqs (was 100000 GPIO); `fan1_target`=1000; `systemctl --failed` empty; network + data + SMART + chrony fine on the same boot.

---

## MUST-2 — DHCP + permanent `.233` — **PASS live 2026-09-15 21:50 UTC**  
**Work-order #2 · ai-handoff MUST-2**

**Intended:** DHCP on `eth0` + permanent `192.168.68.233/22` on **`eth0:1`** (never `:0`).

**Live:** `.233` on `eth0:1`, DHCP `.62` on `eth0`, dhclient PID 1556, `networking.service` **active (exited)** after `systemctl start` without `ifdown`. Interfaces file has **no** `auto eth0:1`; add `.233` only with `|| true`.

This boot logged the old `Address already assigned` at 15:12 (stale stanza). **Cold boot now proven (2026-09-16 08:05 and 08:23 UTC):** both IPs up, dhclient alive, `networking.service` finished OK. Leftover `Address already assigned` / `RTNETLINK answers: File exists` lines are the guarded (`|| true`) pre-up/post-up `.233` re-add — cosmetic, not the old fatal path. Never restore `auto eth0:1 inet static`. Never `ifdown eth0` from the only SSH session.

Files: `/etc/network/interfaces`, `interfaces.bak.pre-dhcp`, `/etc/dhcp/dhclient.conf`, `/etc/dhcp/dhclient-exit-hooks.d/ds115j-static-fallback`, `/etc/systemd/network/10-ds115j-eth0.link`.

---

## MUST-3 — data partition — **DONE 2026-09-15** (verified 21:54 UTC)  
**Work-order #3 · ai-handoff MUST-4**

**Live:** `sda3` 1.8T ext4 LABEL=`data` UUID `2fd25b2a-ceb7-4155-bde9-87dec3d66e2b` on `/srv/data` (`rw,noatime`), writable. fstab UUID + `nofail`. `sda1`/`sda2` starts unchanged.

**Do not** move, reformat, renumber, or overwrite `sda1`/`sda2`. Reboot mount proof is MUST-10.

---

## MUST-4 — disk health (SMART) — **DONE 2026-09-15 20:30 UTC** (verified 21:54)  
**Work-order #4 · ai-handoff MUST-5**

`smartmontools` 7.4-3; `smartmontools.service` enabled/active. `smartctl -H /dev/sda` **PASSED**. No error log. Reallocated/pending 0. Temp ~36 °C. smartd retains the existing health/attribute/log/temperature/tests policy and adds `-m <nomailer> -M exec /usr/local/sbin/smart-amber-led.sh`. SMART health/attribute failures set the bay amber LED steady; a 15-minute timer clears it after recovery. See [`SMART-AMBER-LED.md`](SMART-AMBER-LED.md).

Evidence: [`artifacts/smartctl-a-20260915-2153.txt`](artifacts/smartctl-a-20260915-2153.txt).

---

## MUST-5 — NTP / time — **DONE 2026-09-15 21:10 UTC**
**Work-order #5 · part of ai-handoff MUST-8** (time/locale only; zram/logs are MUST-6)

**Live:** `chrony` 4.6.1-3+deb13u2 **enabled+active**. `systemd-timesyncd` **not installed**. Stock `/etc/chrony/chrony.conf`: `pool 2.debian.pool.ntp.org iburst`, `sourcedir /run/chrony-dhcp`, `rtcsync`. Leap **Normal**, stratum 3, ~0.2 ms vs NTP. Four pool sources reach 377. DHCP NTP hook `/etc/dhcp/dhclient-exit-hooks.d/chrony` is present; `/run/chrony-dhcp` empty until a live dhclient lease (MUST-2).

`hwclock` was missing (Debian split → `util-linux-extra`); installed `--no-install-recommends`. `hwclock -w --utc` then `hwclock -r`: rtc-mv `2026-09-15 21:10:07 UTC`, `/etc/adjtime` UTC. Locale already OK (`en_US.utf8` generated, TZ `Etc/UTC`) — verified, not regenerated.

Evidence: [`artifacts/chrony-tracking-20260915.txt`](artifacts/chrony-tracking-20260915.txt).

**Do not start MUST-6 (zram) or MUST-7 (apt security) in the same turn that only asked for MUST-5 chrony.**

---

## MUST-6 — zram (and log bounds) — **DONE 2026-09-16 ~09:00 UTC**  
**Work-order #6 · part of ai-handoff MUST-8**

234 MiB RAM. **Swap 0 before; now zram.**

**Installed:** `zram-tools` 0.3.7 (via apt). `/etc/default/zramswap`:
```
ALGO=lz4
SIZE=2048      # 2 GiB logical zram device
PRIORITY=100   # higher than any future HDD swap
```

**Live:** `/dev/zram0` lz4, 2 GiB logical, 0 B used, prio 100. `systemctl is-active zramswap`: **active**. No HDD swap in `/etc/fstab`.

**Journal bounds:** `/etc/systemd/journald.conf` set to `SystemMaxUse=50M`, `RuntimeMaxUse=50M`, `MaxRetentionSec=30day`, `Compress=yes`. `systemd-journald` restarted. Current usage 45.6M (will be pruned on next rotation). No `logrotate` changes needed for journald.

**Accept:** modest zram under pressure; bounded journal; no default HDD swap. Cold-boot proof: MUST-10.

---

## MUST-7 — Debian security / updates — **DONE 2026-09-16 ~09:10 UTC**  
**Work-order #7 · ai-handoff MUST-3**

**Before:** sources.list had only `deb http://deb.debian.org/debian trixie main` (no security/updates).  
**Now:** `/etc/apt/sources.list` has all three:
```
deb http://deb.debian.org/debian trixie main
deb http://deb.debian.org/debian trixie-updates main
deb http://deb.debian.org/debian-security trixie-security main
```
`apt-get update` OK (keyring signatures valid for trixie-updates + trixie-security).

`apt-get upgrade --dry-run`: **0 upgraded** (rootfs fully current as installed). No kernel/firmware packages in rootfs — `dpkg -l` shows no `linux-image*`/`linux-headers*`, so nothing apt-side can change the **running kernel** (it comes only from the custom `sda2` uImage). `unattended-upgrades` **not installed** (by design: 256 MiB minimal, controlled manual policy). No apt holds needed — nothing kernel-side is installed.

Kernel/DTB/initramfs/module remain **not** ordinary APT updates (see recovery/deploy, MUST-9).

**Accept:** official suites, valid signatures, controlled userland policy. Do **not** unattended-upgrade the running kernel.

---

## MUST-8 — Samba + nftables (users/ACLs) — **SKIP for now (owner)**  
**Work-order #8 · ai-handoff MUST-6 + firewall from gaps**

No Samba/NFS. No data users. No `nftables`/`ufw`. Only sshd listens.

Prefer minimal SMB. LAN-only. No guest/root-password as the share model.

**Accept:** nftables default-deny input; SSH + SMB from trusted LAN; tested r/w/rename/delete/locking; isolation.

Do this **after** the data volume exists.

---

## MUST-9 — recovery runbook + boot deploy/rollback — **DONE 2026-09-16 ~09:35 UTC**  
**Work-order #9 · ai-handoff MUST-9 / MUST-10 recovery**

U-Boot reads **only `sda2`**. Updating `sda1:/boot` alone does nothing.

**Deliverables (all on helper):**
- Operator runbook: **`/root/ds115j/HANDOFF/RECOVERY-RUNBOOK.md`** — Scenario A (SSH lost, keep `.233`, no `ifdown eth0`), B (U-Boot rollback from `sda2` known-good images + TFTP from `.250`), C (sda2 corrupt → `uRamdisk-recovery-ds115j` + e2fsck), D (no helper), E (automated deploy), F (post-recovery checklist). Full boot-image inventory table with 16-char sha256, UART guidance, **never `ide 0:1`**, never SPI write as first recovery.
- Deploy/rollback script: **`/root/ds115j/scripts/deploy-boot.sh`** (canonical), NAS **`/root/deploy-boot.sh`**. `list` / `dry-prev` / `prev` take **no bundle dir**. `deploy <BUNDLE>` installs the pair; history `*.pre-<STAMP>`. If no ramdisk `.pre-*` exists, `prev` keeps the current ramdisk (never changed on this box). Keeps newest 3 history pairs. Never touches sda1/sda3/SPI/U-Boot env.

**Proof without probing `ide 0:1` or rewriting SPI (2026-09-16 11:31 UTC):** `/root/deploy-boot.sh list` — current `uImage-ds115j` `5ea71e0b…` = TFTP default; ramdisk `dbbd30ec…`; rollbacks `c1688fda…` / `69e60698…`. `/root/deploy-boot.sh dry-prev` would restore **alarm-gpios** `c1688fda…` + keep ramdisk — **not executed, no reboot**. Do not `prev` unless diagnosing MUST-1 with UART.

**Accept:** documented rollback proved without probing `ide 0:1` or rewriting SPI.

---

## MUST-10 — verify (health gate + unattended safety) — **DONE 2026-09-16 ~09:32 UTC**  
**Work-order #10 · ai-handoff MUST-10 + verification**

Real **cold power-cycle** by owner (NAS unplugged ~09:29:50 UTC, replugged, `.233` down ~24 s then back). Operator polled power-off + fresh-boot detection.

**Gate results (all PASS):**
| Check | Result |
|---|---|
| fresh boot | uptime 1 min; kernel booted this cycle |
| failed units | none (`systemctl --failed` empty) |
| network | `.233` static + DHCP `.62` + default route via `.1` |
| data mount | `/dev/sda3` rw,noatime on `/srv/data` |
| zram at boot | `/dev/zram0` lz4 **2G** prio 100 active, 256K used |
| SMART | WD Red WD20EFRX-68EUZN0, SMART enabled |
| udev idle (MUST-1 regression) | `uevent_seqnum` static 1798→1798 over 5 s; no udev CPU in top; live DTB **no** `alarm-gpios` |
| poweroff module | `qnap_poweroff_ds115j` loaded after cold boot |
| time | chrony active stratum 4 (time.cloudflare.com), leap Normal, offset ~2 ms; RTC UTC matches system |
| sda2 hash vs helper | re-`list`ed: current `5ea71e0b…` + pre `c1688fda…`/`69e60698…` all match TFTP |
| boot time | kernel 12.878 s, userspace 36.997 s, graphical 49.875 s |

Watchdog `/dev/watchdog0` exists but **must not** be armed until anti-loop tested. UPS/NUT, front-button shutdown: after burn-in. **Status LED / MCU: done as MUST-11.**

---

## MUST-12 — balanced fan control — **DONE 2026-09-16 ~11:31 UTC** (hysteresis fix)
**Work-order #12 · ai-handoff MUST-12**

### Problem
DS115j stock DSM runs fan automatically based on SoC temperature; after conversion, fan sat fixed at ~1000 RPM regardless of load. First userspace controller (10:55 UTC) tracked temp but used **pwm-delta ≥ 15** as “hysteresis”. At the 58/59 °C band edge, pwm 110 vs 145 is a delta of 35, so the fan **hunted 110↔145 every ~20 s** (FULL-MUST-AUDIT).

### What was proven (2026-09-16, owner-verified)
- `/sys/class/hwmon/hwmon0/temp1_input` = SoC thermal sensor (millidegrees). Same value as `thermal_zone0`.
- `/sys/class/hwmon/hwmon1/pwm1` controls fan 0–255 → **1000–1900 RPM**. Mapping: 20–30 → 1000 RPM, 100 → 1350, 120 → 1500, 200 → 1750, 255 → 1900 RPM (`fan1_max`=1900). **Never write 0.**
- `fan1_target` is the RPM setpoint derived from pwm1. Canonical knob is `pwm1`.

### Solution — `/usr/local/sbin/syno-fan.sh` + helper `/root/ds115j/scripts/syno-fan.sh`

**Balanced curve** (rising edges). Falling edges stay on the current pwm until temp is **2 °C** below the edge that raised it (`HYST_MDEG=2000`):

| SoC temp (°C) rising | pwm | ≈ RPM |
|---|---|---|
| ≤ 45 | 25 | 1000 (quiet idle) |
| 46–52 | 65 | ~1200 |
| 53–58 | 110 | ~1400 |
| 59–63 | 145 | ~1500–1600 |
| 64–68 | 190 | ~1750 |
| 69–73 | 230 | ~1850 |
| ≥ 74 | 255 | 1900 (max) |

- Polls every 20 s. `syno-fan.sh --self-test` proves 57–58 °C does not hunt and ≥75 °C alarm latch/clear **without heating the disk**.
- Sensor missing → pwm 65. `clamp_pwm` rejects 0.
- **MCU alarm:** ≥75 °C → `syno-mcu.sh alarm` once per episode; clears ≤70 °C; re-arms. **Not thermally fired on the box** (unsafe); logic unit-tested.
- Boot race: service `After=systemd-udevd.service systemd-modules-load.service` (no `DefaultDependencies=no`). Script waits up to 60 s and **globs** `hwmon*/pwm1` that has `fan1_target`.

### Acceptance
- Owner sweep (earlier): min 1000 / mid 1500 / max 1900 — audible. Balanced curve chosen.
- `syno-mcu.sh alarm` verified separately (orange-blink + 3 long beeps).
- 11:31 UTC: `--self-test` PASS on NAS + helper; service restart `62°C → pwm=145 fan1_target=1500`; live sample window documented in CURRENT-STATE (stable target, no 110↔145 flip).

### Service: `syno-fan.service`
- `Type=simple`, `WantedBy=multi-user.target`, `After=systemd-udevd.service systemd-modules-load.service`.
- Touched: NAS `/usr/local/sbin/syno-fan.sh` + unit; helper copies. sda1/sda2/U-Boot/SPI untouched.

---

## MUST-11 — status LED / MCU control — **DONE 2026-09-16 ~09:55 UTC**  
**Work-order #11 · ai-handoff MUST-11**

DS115j front-panel PIC16LF1828 connected to UART1 (`/dev/ttyS1`, 9600 8N1). Single-ASCII-byte commands; proven **live** by owner on this unit:

| Command | Byte | Effect (on this unit) |
|---|---|---|
| `'4'` | 0x34 | blue power LED **steady on** |
| `'5'` | 0x35 | blue power LED **blink** |
| `'6'` | 0x36 | blue power LED **off** |
| `'7'` | 0x37 | status LED **off** |
| `'8'` | 0x38 | status LED **green steady** |
| `'9'` | 0x39 | status LED **green blink** |
| `':'` | 0x3A | status LED **orange steady** |
| `';'` | 0x3B | status LED **orange blink** |
| `'2'` | 0x32 | short beep — **audible, verified owner 2026-09-16** |
| `'3'` | 0x33 | long beep — **audible, verified owner 2026-09-16** |

**Do NOT send manually:** `'1'` (power-off, kernel handles at shutdown via `synology,power-off`), `'C'` (hard reset). `'A'`/`'B'` (D8 MB LED) not present on DS115j.

### Delivered

- **`/usr/local/sbin/syno-mcu.sh`** (canonical NAS) + **helper `/root/ds115j/scripts/syno-mcu.sh`** — owner-verified userland driver. Subcommands: `power on|blink|off`, `status off|green|green-blink|orange|orange-blink`, `healthy` (sends `'4'` then `'8'`), `alarm` (status orange-blink + 3 long beeps), `beep short|long`, `ping`.
- **`syno-mcu-boot.service`** (systemd oneshot, `RemainAfterExit=yes`) — enabled + started; at boot sets healthy state (blue steady + status green steady). Transient opens only, so UART1 is **free** for the kernel power-off module at shutdown (no race).

### Boot indicator sequence (added 2026-09-16, owner-approved)

- **`syno-mcu-boot-begin.service`** (`WantedBy=systemd-udevd-kernel.socket`, ~4 s into userspace): power LED **blinks** (`'5'` 0x35) + status LED **orange steady** (`':'` 0x3A). Unit **Description** matches the script (was wrongly “orange blink”).
- **Disk/bay amber — SMART failure only (2026-09-16 12:25 UTC).** The rejected `disk-activity` trigger remains removed. Healthy state is `trigger=none`, `brightness=0`; smartd health/attribute failures set steady `brightness=1`. `/usr/local/sbin/smart-amber-led.sh` is invoked by smartd, and `smart-amber-led.timer` reconciles every 15 minutes so recovered health clears the LED. Manual and simulated-hook tests passed; final state is off. The bay green half remains hardware SATA activity. See [`SMART-AMBER-LED.md`](SMART-AMBER-LED.md).
- **`syno-mcu-boot.service`** (gated `After=network.target networking.service syno-mcu-boot-begin.service`, plus readiness poll in script): when system is actually usable → power LED steady + status LED **green steady** + **one short beep** (`'2'`).
- Readiness gate checks: default route exists, `/srv/data` mounted, zram in `/proc/swaps`; 120 s timeout → stays orange (fail-safe), no beep.
- Verified live 2026-09-16: blink window `10:36:21 → 10:36:52` (~31 s), green + beep exactly at network up; 0 failed units.

### Acceptance (all PASS, 2026-09-16)

- `/dev/ttyS1` present (4,65 root:dialout), stty 9600 raw verified.
- Blue power LED commands `'4'`/`'5'`/`'6'` confirmed visually by owner.
- Status LED commands `'7'`/`'8'`/`':'`/`';'` (green/orange, steady/blink) confirmed visually.
- Beep `'2'`/`'3'` — **audible, both types distinct**, owner-confirmed (device right next to owner).
- `alarm` mode (orange-blink + 3 long beeps) verified live.
- *Beep note: first single-quiet test was missed; explicit retest (3 long + 4 short) confirmed audible, both types distinct. No hardware change was needed — the beeper was always functional.*
- `syno-mcu-boot.service` active; journal clean; both LEDs steady green + blue after boot.
- No race with power-off handler: port held transiently only; kernel module takes UART1 MMIO at shutdown independently.

---

## Still required (do not drop)

### Backup / restore (ai-handoff MUST-7)

One-bay NAS: no RAID. Helper SPI/boot artifacts are **not** user-data backup. Need independent copy + restore drill **before** storing unique data.

### Boot lifecycle packaging (MUST-9 remainder) — **DONE**

Deploy script with current/previous images, read-back, `sync`/unmount `sda2`: **`/root/ds115j/scripts/deploy-boot.sh`** (NAS: `/root/deploy-boot.sh`). Still to be exercised end-to-end on a real reboot when MUST-10 next touches the box.

---

## Explicitly later / optional

Status LED MCU, beeper, network LEDs, USB stick soak test, mDNS/WSD, web UI, external RTC (only if `rtc-mv` fails a long power-loss test), Docker/Plex/Nextcloud (poor fit).

## Change protocol

For every change: state helper vs `sda1` vs `sda2` vs U-Boot vs SPI; preserve UART and `.233`; one logical change; stop on unexplained boot/disk/link/temp/checksum diffs.
