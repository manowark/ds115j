# FULL MUST AUDIT — DS115j Debian

**When:** 2026-09-16 **11:18–11:22 UTC** (read-only; no uImage/SPI/U-Boot writes)  
**NAS:** `ssh root@192.168.68.233` (uptime ~23 min at first probe; boot `2026-09-16 10:55 UTC`)  
**Helper:** this host `192.168.68.250` (`/root/ds115j/HANDOFF/`)  
**Kernel:** `6.12.107+deb13-armmp` · Debian 13.7 trixie armhf  
**Failed units:** none  
**This audit did not** re-send MCU beep/alarm, change pwm, or cold-power the box.

Claimed by prior AI: MUST-1…12 all closed (MUST-8 skip). Independent live check below.

## Per-item table

| Item | Status | Documented on helper? | Live vs claimed |
|---|---|---|---|
| MUST-1 udev/gpio-fan alarm | **DONE** | yes — `MUST-FIXES.md`, `MUST-1-4-VERIFICATION.md`, `CURRENT-STATE.md` | Matches. DTB has **no** `alarm-gpios`; uevent idle. |
| MUST-2 networking | **DONE** | yes — `MUST-FIXES.md`, `CURRENT-STATE.md` (DHCP IP in docs is stale `.62`) | `.233` + DHCP + `networking.service` OK. Cosmetic `Address already assigned` still logged. |
| MUST-3 data | **DONE** | yes | `sda3` LABEL=data → `/srv/data` UUID, rw,noatime, writable. |
| MUST-4 SMART | **DONE** | yes — `MUST-FIXES.md`, `artifacts/smartctl-a-20260915-2153.txt` | smartd active; `smartctl -H PASSED`. |
| MUST-5 NTP | **DONE** | yes — `MUST-FIXES.md`, `artifacts/chrony-tracking-20260915.txt`, `project-context/docs/must-5-ntp.md` | chrony stratum 2, leap Normal, RTC UTC, `timedatectl` synced. |
| MUST-6 zram + journal | **DONE** | yes — `MUST-FIXES.md`, `CURRENT-STATE.md` | zram0 lz4 2G prio 100; journal caps 50M; no HDD swap. |
| MUST-7 apt | **DONE** | yes — `MUST-FIXES.md`, `CURRENT-STATE.md` | `trixie` + `trixie-updates` + `trixie-security`; `apt-cache policy` shows all three. No `linux-image*` / unattended-upgrades. |
| MUST-8 samba/nftables | **SKIP** | yes — owner skip in `MUST-FIXES.md` | No samba/nftables/ufw; listen = sshd + dhclient/chrony only. |
| MUST-9 recovery + deploy | **DONE** (gaps) | yes — `RECOVERY-RUNBOOK.md`, `scripts/deploy-boot.sh` | Runbook + `list` on live sda2 OK. `prev` never booted. TFTP **default** `uImage-ds115j` is still the **old** alarm kernel. |
| MUST-10 cold boot | **DONE** (historical) | yes — `MUST-FIXES.md` §MUST-10 | Not re-run this audit. This boot is a **10:55 UTC reboot** (fan/MCU work), still healthy. Last documented cold cycle ~09:32 UTC. |
| MUST-11 LED / MCU | **DONE** (gaps) | yes — `MUST-FIXES.md` §MUST-11, `LANDMINES.md`, `HISTORY.md` §21; **no** standalone `MUST-11-*.md` | Power + status + beep via UART1 **implemented and journal-proven this boot**. Disk amber GPIO **not driven**. Visual not rechecked this audit. |
| MUST-12 fan | **PARTIAL** | yes — `MUST-FIXES.md` §MUST-12, `LANDMINES.md`, `HISTORY.md` §24; **no** standalone `MUST-12-*.md` | Service tracks SoC temp via `pwm1`. **Not stuck at 1000.** Hysteresis is pwm-delta, so it **hunts** 110↔145 at 57–58 °C. Overheat→MCU alarm not hit live this audit. |

## Evidence (exact commands / results)

### Identity / health

```text
hostname ds115j
Linux ds115j 6.12.107+deb13-armmp … armv7l
Debian GNU/Linux 13 (trixie) 13.7
uptime: 11:18 UTC, up 23 min; boot 2026-09-16 10:55
systemd-analyze: 7.377s kernel + 40.198s userspace = 47.576s
systemctl --failed: 0 units
lsmod: qnap_poweroff_ds115j, gpio_fan
platform: f1012100.poweroff present
dbus: active; /run/dbus/system_bus_socket present
```

### MUST-1

```bash
cat /sys/kernel/uevent_seqnum; sleep 5; cat /sys/kernel/uevent_seqnum
# 1778 → 1778  (delta=0)
test -e /sys/firmware/devicetree/base/gpio-fan/alarm-gpios && echo YES || echo ABSENT
# ABSENT
ls /sys/firmware/devicetree/base/gpio-fan/
# compatible  gpio-fan,speed-map  gpios  name  pinctrl-0  pinctrl-names
ps -eo pcpu,cputime,comm | grep systemd-udevd
# 0.0  00:00:01  systemd-udevd
grep mv64xxx_i2c /proc/interrupts
# 44: 0  … mv64xxx_i2c
```

Residual: `/etc/udev/rules.d/01-gpio-fan.rules` still present (`nowatch` + comments). Harmless.

Helper live DTS `/root/ds115j/linux/arch/arm/boot/dts/marvell/ds115j.dts` SHA `89bc51c8…` has **no** `alarm-gpios`. HANDOFF `artifacts/ds115j.dts` SHA `8492da22…` **still has** `alarm-gpios` (stale copy).

### MUST-2

```bash
ip -4 addr show eth0
# inet 192.168.68.233/22 … eth0:1   (permanent)
# inet 192.168.68.77/22  … secondary dynamic eth0   (DHCPACK from .1; lease ~5851s)
# (docs still say .62 — DHCP moved; expected)
systemctl is-active networking.service   # active
# ExecStart ifup -a status=0; dhclient PID 377 alive IF_METRIC=100
# default via .1 metric 100 and metric 200
```

This boot journal:

```text
10:55:45 ifup: Error: ipv4: Address already assigned.
10:55:45 ifup: RTNETLINK answers: File exists
```

Count this boot: **1** “Address already assigned”. Guarded `|| true` path; unit succeeded. **Not** the old fatal `auto eth0:1`. `/etc/network/interfaces` has no `auto eth0:1`.

### MUST-3

```text
sda3 LABEL=data UUID=2fd25b2a-ceb7-4155-bde9-87dec3d66e2b ext4
findmnt /srv/data → /dev/sda3 ext4 rw,noatime
fstab: UUID=2fd25b2a-…  /srv/data  ext4  defaults,noatime,nofail  0  2
touch /srv/data/.audit-write-$$ → WRITE_OK (removed)
df: 1.8T, ~2.1M used
sda1/sda2 starts untouched (rootfs + boot labels match prior)
```

### MUST-4

```text
systemctl is-active smartmontools smartd → active / active
smartctl -H /dev/sda → PASSED
Reallocated 0, Current_Pending 0, Temp 35 °C, Power_On_Hours 48625
smartd.conf: /dev/sda -d sat -a -o on -S on -s (S/../.././02|L/../../6/03) -W 4,45,50
```

### MUST-5

```text
chrony active+enabled; systemd-timesyncd not in play
chronyc tracking: stratum 2, leap Normal, ~0.04 ms vs NTP
sources reach 377 (pool + time.cloudflare.com)
timedatectl: System clock synchronized: yes; RTC in local TZ: no
hwclock -r --utc matches system UTC
locale LANG=en_US.UTF-8  TZ Etc/UTC
```

### MUST-6

```text
/etc/default/zramswap: ALGO=lz4 SIZE=2048 PRIORITY=100  (no PERCENT)
/proc/swaps: /dev/zram0  2097148 kB  prio 100
zramctl: lz4  2G logical
fstab: no swap entries
journald: SystemMaxUse=50M RuntimeMaxUse=50M MaxRetentionSec=30day Compress=yes
journalctl --disk-usage: 45.6M
```

### MUST-7

```text
/etc/apt/sources.list:
  deb http://deb.debian.org/debian trixie main
  deb http://deb.debian.org/debian trixie-updates main
  deb http://deb.debian.org/debian-security trixie-security main
apt-cache policy: trixie, trixie-updates, trixie-security all present (armhf)
dpkg: no linux-image* / linux-headers* / unattended-upgrades
```

`apt-get update` not re-run this audit (write to apt lists). Policy already reflects a prior successful update.

### MUST-8

```text
dpkg: no samba / nfs-kernel-server / nftables / ufw installed
ss -lntup: tcp/22 sshd; udp/68 dhclient; udp/323 chronyd
```

### MUST-9

Helper:

- `/root/ds115j/HANDOFF/RECOVERY-RUNBOOK.md` (scenarios A–F, inventory table)
- `/root/ds115j/scripts/deploy-boot.sh` SHA `7323aa90…` (byte-identical to NAS `/root/deploy-boot.sh`)

Live `list` (RO mount):

```bash
/root/deploy-boot.sh /root list
# CLI requires a dummy BUNDLE_DIR even for list
```

```text
sda2:/boot/uImage-ds115j              6060176  5ea71e0bc69a17ae269e278eedc28288702f1259edffefd97d420e01141ae3e8
sda2:/boot/uRamdisk-hdd-ds115j        3300604  dbbd30ec2c3772e2816eaa5e3295b0580a357fc93458dcb3bf063bf7bf65cd75
uImage-ds115j.pre-noalarm-20260916    6060232  c1688fda25f1472d…
uImage-ds115j.pre-poweroff-i2c-20260915 6060240  69e60698a993b487…
```

Helper TFTP:

```text
/srv/tftp/uImage-ds115j               c1688fda…   ← DEFAULT recovery name = OLD kernel (alarm-gpios)
/srv/tftp/uImage-ds115j.new-noalarm   5ea71e0b…   ← matches live sda2
/srv/tftp/uRamdisk-hdd-ds115j         dbbd30ec…   ← matches sda2
```

`deploy-boot.sh prev` **not** exercised on a real reboot (documented). No SPI / `ide 0:1`.

### MUST-10

Not re-proven with unplug this session. Documented owner cold cycle 2026-09-16 ~09:32 UTC in `MUST-FIXES.md`. Current boot 10:55 UTC still:

- 0 failed units
- `.233` + DHCP + default route
- `/srv/data` mounted
- zram lz4 2G
- SMART PASSED
- uevent idle, no `alarm-gpios`
- `qnap_poweroff_ds115j` loaded
- chrony synced
- sda2 hashes match TFTP `new-noalarm` + ramdisk

### MUST-11 — what was implemented

**Not disk-amber activity LED.** Front **power (blue)** and **status (green/orange)** plus **beeper**, via PIC16LF1828 on **UART1** `/dev/ttyS1` 9600 8N1. Userspace: `/usr/local/sbin/syno-mcu.sh` (helper copy identical SHA `7049ebcb…`).

| Byte | Effect (claimed / this-boot journal) |
|---|---|
| `'5'` 0x35 | power blink — sent 10:55:14 `begin` |
| `':'` 0x3A | status **orange steady** — sent 10:55:14 |
| `'4'` 0x34 | power steady — sent 10:55:46 `ready` |
| `'8'` 0x38 | status green steady — sent 10:55:46 |
| `'2'` 0x32 | short beep — sent 10:55:46 |

Services: `syno-mcu-boot-begin.service` (WantedBy `systemd-udevd-kernel.socket`) + `syno-mcu-boot.service` (After network; `syno-mcu-boot.sh ready` waits for route + `/srv/data` + zram, 120 s). Both **enabled+active** this boot. `syno-mcu.sh ping` → OK. Port not held (open/close per command). Kernel power-off module still loaded (`f1012100.poweroff`).

**Disk amber:** `/sys/class/leds/synology:amber:disk` exists (`leds_gpio`), `brightness=0`, `trigger=[none]`. **Not** tied to `disk-activity`. Historical DTS “disk amber works” ≠ MUST-11 MCU work.

**Gaps:** this audit did **not** visually reconfirm LEDs/beep. `syno-mcu-boot-begin.service` **Description** says “status LED orange **blink**”; script sends orange **steady** (`':'`). `alarm` (`';'` + 3× `'3'`) not re-fired.

### MUST-12 — fan

Control: `/usr/local/sbin/syno-fan.sh` + `syno-fan.service` **enabled+active** (helper SHA match `16b05ecc…`). Reads `hwmon0/temp1_input` (SoC, same as `thermal_zone0`), writes `hwmon1/pwm1`. `gpio_fan` loaded. `pwm1_enable=1`. Never unbound.

Live at 11:18: temp **62.4 °C**, pwm **145**, `fan1_target` **1500**, `fan1_max` 1900. Journal shows curve tracking 66→190, 68→230, 60→145, then idle around 57–58 °C.

**Not working as claimed hysteresis:** `HIST_DELTA=15` compares **pwm** bands (110 vs 145 = 35 ≥ 15), so at the 58/59 °C band edge the fan **oscillates every ~20 s** (57→110, 58→145) for many minutes. Not stuck; **hunting**.

**Boot race (this boot, old script):** `10:55:14 cannot create /sys/class/hwmon/hwmon1/pwm1: Directory nonexistent` then a log line `66°C -> pwm=190` (write may have failed). Service restarted 10:57:47 after script update (wait loop added). Current script waits up to ~30 s for `pwm1`; **not re-proven on a later boot**.

Overheat ≥75 °C → `syno-mcu.sh alarm`: **code present, not thermally triggered this audit**.

### Soft poweroff + boot hashes + helper package

| Check | Result |
|---|---|
| `qnap_poweroff_ds115j` loaded + autoload `/etc/modules-load.d/qnap-poweroff-ds115j.conf` | yes |
| vermagic `6.12.107+deb13-armmp` | match running kernel |
| sda2 current uImage | `5ea71e0b…` = TFTP `uImage-ds115j.new-noalarm` |
| sda2 ramdisk | `dbbd30ec…` = TFTP `uRamdisk-hdd-ds115j` |
| TFTP **name** `uImage-ds115j` | still `c1688fda…` (pre-noalarm) |
| HANDOFF core files present | `00-START-HERE.md` ACCESS LANDMINES MUST-FIXES CURRENT-STATE MUST-1-4-VERIFICATION HISTORY HELPER-TREE PASTE RECOVERY-RUNBOOK MANIFEST artifacts/ |
| `00-START-HERE.md` ordered MUST list | **STALE** (still says udev not done; omits MUST-11/12) |
| `CURRENT-STATE.md` snapshot table | missing MUST-7 / MUST-12 before this audit |
| Dedicated MUST-11 / MUST-12 verification files | **no** |
| `deploy-boot.sh` / `syno-*.sh` helper vs NAS | **identical** |

## Gaps (do later; not done in this audit)

1. **MUST-12 hysteresis** — use temperature hysteresis (or stickiness) so 57–58 °C does not flip pwm 110↔145 every poll.
2. **MUST-12 boot** — confirm wait-loop on a **fresh reboot** (this 10:55 boot used the pre-wait script for ~2 min).
3. **TFTP default image** — promote `uImage-ds115j.new-noalarm` → `/srv/tftp/uImage-ds115j` (or document that TFTP default still has alarm-gpios). Runbook already notes the split; recovery Scenario B local rollback is fine.
4. **`deploy-boot.sh prev`** — never actually booted a previous pair.
5. **MUST-11 disk amber** — still unused (`trigger=none`). Wire `disk-activity` only if owner wants bay LED.
6. **MUST-11 Description** — “orange blink” vs script orange **steady**.
7. **Stale helper docs** — `00-START-HERE.md` MUST list; HANDOFF `artifacts/ds115j.dts` still has `alarm-gpios`; `CURRENT-STATE` DHCP `.62`.
8. **Still open (not in 1–12):** independent backup/restore drill; burn-in before watchdog/UPS; `deploy` end-to-end with reboot.

## Verdict

Prior AI **did** implement MUST-1…7, 9–11 and skip 8; MUST-12 **exists and tracks temperature** but **does not fully match** “hysteresis / not hunting”. Claims of “all MUST closed” are **mostly true**, with MUST-12 **PARTIAL** and documentation/TFTP leftovers.

## Follow-up (same day, 11:31 UTC) — gaps closed

| Gap | Result |
|---|---|
| MUST-12 °C hysteresis | **PASS** — `syno-fan.sh --self-test`; live 58.8 °C stayed pwm 145 / 1500 (no 110 flip) |
| MUST-12 overheat path | **PASS (logic)** — unit test TRIGGER at 75 / CLEAR at 70; not thermally forced |
| MUST-12 boot race | Service no longer `DefaultDependencies=no` on udev socket only; waits up to 60 s + glob pwm1. **Not re-proven with a new reboot** |
| TFTP default | **PASS** — `/srv/tftp/uImage-ds115j` now `5ea71e0b…`; old `c1688fda…` versioned |
| MUST-11 Description | **PASS** — orange **steady** |
| MUST-11 disk amber | **REVERTED** — `disk-activity` on amber made the bi-color bay LED blink orange; owner wants green. Amber back to `trigger=none`/`brightness=0`; rule uninstalled |
| `deploy-boot.sh prev` | `list` + `dry-prev` **PASS**; actual `prev`+reboot **not** done (would install alarm-gpios kernel) |
| Docs / DTS artifact | `00-START-HERE.md` rewritten; `artifacts/ds115j.dts` = live no-alarm DTS |

See [`CURRENT-STATE.md`](CURRENT-STATE.md).
