# MUST-1..5 verification

**Latest recheck:** 2026-09-16 **08:26 UTC** — **MUST-1 now PASS** (see "MUST-1 PASS" below). Prior 2026-09-15 22:02 UTC run (this boot ~15:12) documented below for history.

| MUST | Verdict | Notes |
|---|---|---|
| MUST-1 udev / gpio-fan IRQ | **PASS (08:26 UTC)** | DTB no `alarm-gpios`; seqnum static; udev 1 s CPU / 1.4 %; IRQ 44 = `mv64xxx_i2c`. |
| MUST-2 DHCP + `.233` | **PASS + cold boot** | Dual IP on both 08:05 and 08:23 cold boots; dhclient alive. |
| MUST-3 data partition | **PASS** | `sda3` `/srv/data` mounted rw,noatime at boot. |
| MUST-4 SMART | **PASS** | smartd + `smartctl -H PASSED`. |
| MUST-5 NTP / locale | **PASS** | chrony active, rtc-mv UTC, `en_US.utf8`. |

`systemctl --failed`: **empty** (both boots). Swap: **0B**. MUST-8 samba/nftables: **skip**.

---

## MUST-1 — PASS (2026-09-16 08:23–08:26 UTC, new kernel)

Deployed `uImage-ds115j.new-noalarm` (`5ea71e0b…`, built 2026-09-15 23:27, DTB without gpio-fan `alarm-gpios`; zImage identical to previous). Rebooted via SSH at 08:22 UTC. Same-boot checks:

```text
Live DTB: /sys/firmware/devicetree/base/gpio-fan/  →  no alarm-gpios entry (good)
uevent_seqnum 1778 → 1778 over 5s     (was ~10–100/s climbing)
systemd-udevd  TIME 00:00:01, %CPU 1.4  (was 34.794s in ~9min)
IRQ 44        mv64xxx_i2c, 0 irqs     (was 100000 GPIO fan alarm, "IRQ disabled")
fan1_target   =1000   fan1_alarm=0
systemctl --failed: empty
```

Full health on same boot: `.233` (eth0:1) + DHCP `.62` + dhclient; `sda3` mounted rw,noatime; SMART PASSED; chrony active; `gpio_fan` + `qnap_poweroff_ds115j` loaded.

Setup note: `sda2` keeps previous images `uImage-ds115j.pre-noalarm-20260916` (`c1688fda…`) and `uImage-ds115j.pre-poweroff-i2c-20260915` (`69e60698…`). TFTP `uImage-ds115j.new-noalarm` added; `/srv/tftp/uImage-ds115j` unchanged (`c1688fda…`) until the recovery runbook is written.

---

## Prior record (2026-09-15 22:02 UTC) for history

```text
systemd-udevd: active since 21:52:44 UTC (~9 min)
Main PID 3739  CPU: 34.794s
udev-worker PID 4106  TIME 0:18 (~4% CPU)
uevent_seqnum 328340 → 328360 in 2s   (~10/s)
/run/udev/queue: absent
udevadm settle --timeout=15: exit 0
udevadm monitor --kernel: 18 change events in 2s
IRQ 44: 100000  f1018140.gpio 6 Edge  GPIO fan alarm
gpio-38 (alarm) in hi (act lo) - IRQ disabled
fan: name=gpio_fan target=1000 alarm=0  SoC temp=63146 (~63.1 °C)
Live DT: /sys/firmware/devicetree/base/gpio-fan/alarm-gpios exists (12 bytes)
  od: 00 00 00 16  00 00 00 06  00 00 00 00   → gpio1 pin 6, flags 0
```

`/etc/udev/rules.d/01-gpio-fan.rules`: comments + `OPTIONS+="nowatch"`. systemd 257 rejects `ignore_device`/`last_rule`; GOTO labels are per-file. **udev cannot drop the storm.** Kernel still emits with udevd stopped (proven 21:52 UTC).

**Finish MUST-1:** deploy uImage whose DTB has **no** gpio-fan `alarm-gpios` (helper DTS already matches). UART; keep previous `sda2` image. Do **not** unbind `gpio-fan` (fan → 0). No NAS DT overlay configfs.

---

## MUST-2 — PASS live (22:02 UTC)

```text
networking.service: enabled, active (exited) since 21:50:28 UTC
ExecStart ifup -a: status=0/SUCCESS
eth0:1  192.168.68.233/22  scope global
eth0    192.168.68.62/22   secondary dynamic   valid_lft 4624sec
dhclient -v -4 … eth0  PID 1556 since 20:28 UTC
lease 192.168.68.62 expire 2026/09/15 23:19:29 UTC
ifstate: lo=lo eth0=eth0
```

`/etc/network/interfaces`: `iface eth0 inet dhcp` + `pre-up`/`post-up` `ip addr add 192.168.68.233/22 … label eth0:1 || true`. **No** `auto eth0:1`.

This **boot** journal still has 15:12 UTC `Address already assigned` / `failed to bring up eth0:1` (old stanza). Live repair at 21:50 did not `ifdown`. **Cold-boot proof = MUST-10.** Never restore `auto eth0:1`. Never `ifdown eth0` from the only SSH session.

Routes: default via `.1` (unmetric + metric 100 + metric 200).

---

## MUST-3 — PASS (22:02 UTC)

```text
sda1  64G  ext4 rootfs  fc9ea304-14d5-4494-a117-7dfda838e18b  /           start=63
sda2 128M  ext2 boot    eec9c4e3-7c83-40b6-af29-e28c4f228baa               start=134217791
sda3  1.8T ext4 data    2fd25b2a-ceb7-4155-bde9-87dec3d66e2b  /srv/data   start=134481920
/dev/sda3 on /srv/data type ext4 (rw,noatime)
fstab: UUID=2fd25b2a-ceb7-4155-bde9-87dec3d66e2b  /srv/data  ext4  defaults,noatime,nofail  0  2
df /srv/data: 1.8T  2.1M used
write /srv/data/.must-recheck-write: OK (created 22:02, removed)
```

`sda1`/`sda2` starts unchanged. Reboot mount = MUST-10.

---

## MUST-4 — PASS (22:02 UTC)

```text
smartmontools 7.4-3 armhf
smartmontools.service enabled+active since 20:30:47 UTC  smartd PID 1938
/etc/smartd.conf: /dev/sda -d sat -a -o on -S on -s (S/../.././02|L/../../6/03) -W 4,45,50
smartctl -H /dev/sda: PASSED
Error log: No Errors Logged
Reallocated_Sector_Ct 0  Current_Pending_Sector 0  UDMA_CRC 0
Temperature 36 °C  Power_On_Hours 48622
fan1_target still 1000
```

---

## MUST-5 — PASS (22:02 UTC)

```text
chrony enabled+active
Reference ID: dns2.campus-rv.net  Stratum 3  Leap Normal
System time ~0.05 ms slow of NTP  RMS offset ~0.09 ms
hwclock -r --utc: 2026-09-15 22:02:29 UTC
/etc/adjtime: UTC
LANG=en_US.UTF-8  locale -a: C.utf8 en_US.utf8
Swap 0 (MUST-6 not started)
```

`timedatectl` unavailable (no dbus) — expected.

---

## Modules (confirm)

`gpio_fan` and `qnap_poweroff_ds115j` loaded.

## What the 2026-09-16 session did not do

No SPI/`saveenv`, no `ide 0:1`, no `sda1`/`sda2` partition layout change, no `ifdown eth0`, no gpio-fan unbind, no samba/nftables. U-Boot untouched. UART port left free (only a passive RX `cat` capture used during the 08:22 reboot, then stopped).
