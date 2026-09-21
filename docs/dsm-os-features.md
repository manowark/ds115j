# DSM OS/hardware features → Debian parity map (2026-09-21)

Grounded in the extracted DSM build (`hda1-rootfs`: `/etc.defaults/rc*`,
`synoinfo.conf`, `sysctl.conf`, `DiskApmSet.sh`, `synotimecontrol`,
`synobios.ko` strings, SPI dump U-Boot env). Only **OS-oriented** settings that
affect the system/hardware as a whole — nothing about packages/UI.

Legend: ✅ replicated on our Debian · ⚠️ replicated but different · 🆕 candidate
· ✖️ not applicable on this unit.

## Hardware-level

| DSM item | Evidence in DSM | Debian status | Notes |
|---|---|---|---|
| **Power button** | `scemd` reads `0x30`; `SynologyPowerButton` | ✅ | `syno-powerbtn`, arming via rc bytes, persistence proven |
| **Fan control** | `synobios SetFanStatus/PWMFanSpeedMapping`; `support_fan=yes`, `support_fan_adjust_dual_mode=yes` | ✅ | `syno-fan` (SoC hwmon `pwm1`, temp curve). Dual mode (auto/manual) not needed — always auto |
| **CPU clock** | U-Boot env, `cpuclk` | ✅ | **800 MHz confirmed live** (`clk_summary`: `cpuclk 800000000`, DDR 200 MHz). `BogoMIPS 33.33` is bogus ARM calibration, ignore it |
| **RTC** | `rtc-mv`; `nanotime` wake | ✅ | `rtc0` + `wakealarm` present, `hctosys` works, chrony syncs |
| **RTC alarm / auto power-on** | `support_auto_poweron=yes`, `supportrcpower=yes`, `synotimecontrol` | ✖️ | **LIVE-TESTED 2026-09-21 — DOES NOT WORK with our poweroff path.** Armed `wakealarm` for +3 min (@12:40:30 UTC), ran `poweroff` (PIC PSU-cut), box stayed off. After the next button power-on the alarm register was cleared. **However the RTC *calendar* survives a full PSU cut** (hwclock correct after cold boot — coin-cell/supercap on the standby rail) — only the SoC-internal alarm line fails to wake a fully-PSU-cut board (in DSM, "auto power on" relies on a low-power SoC halt state instead of full PSU cut). Tool kept in repo as a manual convenience; don't rely on it for scheduled wake.
| **Watchdog** | (DSM does not feed it either) | 🆕 | SoC **Orion Watchdog** present at `/dev/watchdog0` (timeout 257 s, currently `inactive` — nothing feeds it). Enabling `RuntimeWatchdogSec` makes a hung kernel reboot instead of staying dead |
| **USB VBUS** | DTB `usb-regulator@2` (MPP44) | ✅ | `usb-vbus-fix` |
| **USB autosuspend** | DSM keeps storage awake | ⚠️/🆕 | Our kernel: `usbcore.autosuspend=2` (module param 2 s). Both attached devices currently `control=on`; make it permanent: `options usbcore autosuspend=-1` |
| **USB storage drivers** | `usb-storage`, `uas` | ✅ | Both buses live; `uas` on the ASMedia bridge |
| **HW RNG** | `/dev/hwrng` (Armada RNG) | ✅ | Kernel feeds primary CRNG from hwrng in 6.x; `entropy_avail=256` is fine |
| **HW crypto (CESA)** | `marvell-cesa` | ✅ | Driver bound; kernel crypto API (IPsec, dm-crypt) uses it automatically |
| **Thermal zone** | `f1018300.thermal` (Armada 370 SoC temp) | ✅ | `thermal_zone0` read-only — no trip points configured, fan is the cooler |
| **CPU idle** | — | ⚠️ | **No `cpuidle` in sysfs** — this kernel build has no CPU_IDLE states for Armada 370 (slight idle-power cost, functionally irrelevant). DSM does not add it either |
| **Disk APM** | `DiskApmSet.sh` | ✅ | This WD disk: `APM not supported` — nothing to set. `hdparm -S 120` standby gives the hibernation `support_disk_hibernation=yes` |
| **SMART** | `smartd.conf`, `supportsmart=yes` | ✅ | `smart-amber-led` |

## OS-level

| DSM item | DSM value | Our Debian | Recommend |
|---|---|---|---|
| `kernel.panic` | 3 (sysctl) | **10** (`panic=10` bootarg) | keep 10 |
| `net.core.somaxconn` | 65535 | 4096 | 🆕 **apply 65535** — file-server friendly (many SMB/NFS clients) |
| `net.ipv4.tcp_tw_reuse` | 1 | 2 (6.x default: enabled+safe) | keep 2 |
| `net.ipv6.conf.default.accept_ra_defrtr` | 0 | unset (we use static/DHCP) | 🆕 set 0 via sysctl.d for parity |
| IPv6 in general | `disable_ipv6` toggles in rc.network | IPv4-only LAN | **leave IPv6 addressed by SLAAC/router**; nothing to change |
| `ip_forward` | 1 (router mode) | 0 | keep 0 — single NIC, not a router |
| `somaxconn` echo | rc pieces | — | see above |

## Boot-kernel cmdline (DSM vs ours)

DSM U-Boot env (SPI dump):
```
console=ttyS0,115200 ip=off initrd=0x8000040,8M root=/dev/sda1 rw
syno_hw_version=DS115j ihd_num=0 netif_num=1 flash_size=8
```
Our bootargs:
```
console=ttyS0,115200 earlyprintk root=LABEL=rootfs rootwait rw panic=10
```
✅ Equivalent essentials (console, root, rw). DSM's `syno_*` kcmdline vars are
consumed by its patched kernel + synobios — meaningless on Debian.

## Synology-only kernel sysctls (not portable)

`/proc/sys/kernel/syno_*` (topology, MACs, hw version), `supportledbehaviorv2`
(we replicate the LED bytes in rc ourselves). These need Synology's patched
kernel — **skip**, our userspace handles their functions.

## Chosen actions (additive, no risk)

1. `/etc/sysctl.d/90-ds115j-tune.conf` — `somaxconn=65535`,
   `accept_ra_defrtr=0`.
2. `/etc/modprobe.d/usbcore-autosuspend-off.conf` — `options usbcore
   autosuspend=-1` (USB storage never sleeps).
3. `/etc/systemd/system.conf.d/90-ds115j-watchdog.conf` —
   `RuntimeWatchdogSec=60` → Orion watchdog feeds; a hard kernel hang reboots
   the NAS ~60 s later instead of leaving it dead until a manual power-cycle.
   Applied on next boot (systemd reads system.conf.d at manager start).
4. RTC power-schedule script (`scripts/rtc-power-schedule.sh`) — manual tool
   (`wakealarm` read/write). **LIVE-TESTED 2026-09-21: does NOT wake the box**
   after a full PSU cut (our poweroff kills the SoC RTC alarm line; only the
   RTC calendar keeps time on the standby rail). Do not rely on it for
   scheduled wake-ups. Keep the script = harmless RTC utility.

Revert = delete the file / reset sysctl. None of them writes to the PIC.