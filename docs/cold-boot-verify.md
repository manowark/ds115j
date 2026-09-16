# REBOOT VERIFY — DS115j daily-ready (2026-09-16)

**When:** 2026-09-16 **11:58–12:06 UTC**  
**NAS:** `ssh root@192.168.68.233`  
**Helper:** `192.168.68.250`  
**Method:** full `reboot` (userspace + kernel restart from HDD). **Not** `poweroff`.  
**Verdict: daily-ready YES** for the owner-scoped slice (no Samba, no nftables, no backups, no burn-in).

## Cold vs reboot (read this first)

| Action | Done? | Why |
|---|---|---|
| Pre-reboot read-only baseline | **yes** 11:58:34 UTC | uptime 1h03 from boot 10:55 UTC; hashes/services/fan/LED/mounts/net captured |
| `reboot` | **yes** issued 11:58:57 UTC; ping dropped 11:59:03; SSH back 12:00:53 UTC | boot timestamp **2026-09-16 11:59 UTC** |
| True PSU cut (`poweroff` + front button) | **no** | `qnap_poweroff_ds115j` cuts PSU; **nobody is at the box to press the button**. WOL not usable (`ethtool` printed no Wake-on-LAN lines). Leaving the NAS off would strand it. |
| Historical PSU cold | already proven ~09:32 UTC same day | see `MUST-FIXES.md` MUST-10 |

**Owner one-liner if they want PSU-cut proof again:** stand at the DS115j, `ssh root@192.168.68.233` → `poweroff`, wait for PSU cut, press the **front power button**, confirm SSH on `.233`. Do not run `poweroff` remotely with no one at the chassis.

This session is a **warm reboot** in the sense of no PSU cut, and a **full HDD boot-path restart** (kernel + userspace from `ide 0:2`). That is what was verified.

## Daily-ready table

| Item | Result | Evidence |
|---|---|---|
| Boots from HDD `ide 0:2` / Debian / SSH `.233` | **PASS** | SSH after reboot on `.233` only. `who -b` = `2026-09-16 11:59`. Root `LABEL=rootfs` on `sda1`. U-Boot still loads `sda2` (`ide 0:2`); no `ide 0:1` used. |
| Kernel / cmdline / no panic loop | **PASS** | `6.12.107+deb13-armmp`. cmdline `console=ttyS0,115200 earlyprintk root=LABEL=rootfs rootwait rw panic=10`. `systemd-analyze` 7.667s kernel + 39.341s userspace = **47.008s**. dmesg: no Oops/Call Trace/panic. |
| `systemctl --failed` empty | **PASS** | `0 loaded units listed` at 12:01 and 12:05. |
| `qnap_poweroff_ds115j` loaded | **PASS** | `lsmod`: `qnap_poweroff_ds115j`, `gpio_fan`. |
| Ethernet rgmii, ping GW, DHCP + `.233`, networking, dhclient | **PASS** | dmesg `configuring for phy/rgmii-id`; PHY **Marvell 88E1318S**; link 1G full. `eth0:1` **`.233/22` forever**; DHCP **`.77/22`** secondary (lease ~7132s). `networking.service` **active**, `ifup` status=0. `dhclient` PID 401 alive `IF_METRIC=100`. ping GW `.1` 3/3. MAC live **`00:11:32:4d:c3:b8`**. Cosmetic: one `Address already assigned` / `RTNETLINK File exists` (guarded `ip addr add … \|\| true`). Early dmesg `Using random mac` before `.link` apply — **not** the live MAC. |
| MUST-1 no alarm-gpios; udev idle; uevent low | **PASS** | `ALARM_GPIOS=ABSENT`. gpio-fan nodes: compatible, speed-map, gpios, pinctrl — no `alarm-gpios`. uevent_seqnum **1779→1779** (5s) and still 1779 after 6+ min. `systemd-udevd` ~**0.2%** CPU, cputime **00:00:01** after 6m27s. `mv64xxx_i2c` count **0**. |
| MUST-3 `/srv/data` rw | **PASS** | `/dev/sda3` ext4 `rw,noatime` UUID `2fd25b2a-ceb7-4155-bde9-87dec3d66e2b`. `touch` WRITE_OK. sda1/sda2 labels untouched. |
| MUST-4 smartd + SMART PASSED | **PASS** | `smartd`/`smartmontools` active. `smartctl -H /dev/sda` **PASSED**. |
| MUST-5 chrony + RTC | **PASS** | chrony active; leap **Normal**; `System clock synchronized: yes`; RTC UTC matches. `rtc-mv` registered as rtc0, set clock at boot from RTC. |
| MUST-6 zram + journal bound | **PASS** | zram0 **lz4 2G** prio 100. journald `SystemMaxUse=50M` `RuntimeMaxUse=50M` `MaxRetentionSec=30day`. journals **45.6M**. |
| MUST-7 apt trixie-security + updates | **PASS** | sources: trixie + trixie-updates + trixie-security. **`apt-get update` → `APT_UPDATE_OK`**. `apt-cache policy` shows all three. No full upgrade. |
| MUST-9 recovery + uImage SHA | **PASS** | `/root/deploy-boot.sh /root list` live. sda2 `uImage-ds115j` = helper TFTP `/srv/tftp/uImage-ds115j` = **`5ea71e0bc69a17ae269e278eedc28288702f1259edffefd97d420e01141ae3e8`** (6060176 B). ramdisk `dbbd30ec…`. `prev` not written. |
| MUST-11 LED/MCU | **PASS** | `syno-mcu.sh ping` → `OK — /dev/ttyS1 present`. This boot: begin **11:59:35** blink + orange steady; ready **12:00:06** blue/green steady + short beep. Disk amber trigger **`[disk-activity]`**. Visual eyeball not re-done (no operator at chassis). |
| MUST-12 fan wait-loop **this boot** | **PASS** | Service started **11:59:46**; found `hwmon1/pwm1` at **11:59:52** (~6s wait, no FATAL). First set `65°C → pwm=190 target=1750`, then `60°C → pwm=145 target=1500`. Target **never 0**. 12 samples **12:02:33–12:05:51**: **pwm=145 / target=1500** while SoC **60.9→58.0 °C** (old hunt would drop to 110 at 58 °C). Journal: no 110↔145 flip. Brief rise to pwm=190 at 12:01:53 (64 °C during `apt-get update`) then back — pwm **responds to temp**. |
| Fan / disk LED GPIO / rtc-mv | **PASS** | hwmon0 thermal, hwmon1 gpio_fan pwm1+fan1_target. LED `synology:amber:disk`. `rtc-mv f1010300.rtc`. |
| TFTP default uImage | **PASS** | `/srv/tftp/uImage-ds115j` SHA **`5ea71e0b…`** (matches sda2). Alias `uImage-ds115j.new-noalarm` same. Old alarm image kept as `pre-alarm-gpios-c1688fda`. |

MUST-8 Samba / nftables: **skip** (owner). Not installed, not changed.

## Pre-reboot snapshot (11:58:34 UTC)

- Boot 10:55 UTC, up 1h03, failed units 0, `.233` + DHCP `.77`, fan pwm=145 target=1500, udev 0.0%, alarm-gpios ABSENT, uImage `5ea71e0b…`.

## Gaps / cosmetics (not blockers for daily Linux)

1. **True PSU cold cycle** not repeated this session — historical proof stands; owner button required.
2. **ifup** still logs one `Address already assigned` — unit still succeeds; do not restore `auto eth0:1`.
3. **dmesg random MAC** until systemd `.link` pins `00:11:32:4d:c3:b8` — live interface is correct.
4. **Out of scope left undone:** Samba, backups, nftables, Docker, SSH hardening, burn-in, watchdog.
5. `deploy-boot.sh prev` still points at **alarm-gpios** `c1688fda…` — do not `prev` + reboot without UART.

## Landmines honored

No `ide 0:1`, no wipe sda1/sda2, no `ifdown eth0`, no gpio-fan unbind, no `saveenv`/SPI, fan never 0, **no `poweroff`**.
