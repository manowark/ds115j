# CURRENT-STATE — live NAS probe

**When:** 2026-09-16 **12:06 UTC** after **`reboot`** (boot **11:59 UTC**). Full checklist: [`COLD-BOOT-VERIFY.md`](COLD-BOOT-VERIFY.md). Prior MUST-12 hysteresis 11:31 UTC; independent audit 11:22 UTC: [`FULL-MUST-AUDIT.md`](FULL-MUST-AUDIT.md).

## Verdict snapshot

| Item | State |
|---|---|
| USB VBUS fix (2026-09-20) | **FIXED** — DTB now has `regulators/usb-regulator@2` (MPP44, GPIO_ACTIVE_LOW, always-on); **both USB ports live**: flash `13fe:1e00` on usb1 + ASMedia `174c:1153` on usb2; `/dev/sdb` readable at 9.3 MB/s |
| Power button (2026-09-21) | **✅ WORKING, ARMED, VERIFIED LIVE** — `syno-powerbtn.service` + `syno-powerbtn-arm.service`. Press-and-hold ~2 s → PIC `0x30` → clean `poweroff` via `qnap_poweroff_ds115j` (proven twice; arming survives power-off). Config: `TRIGGER_BYTES="30"`, `SETTLE_SEC=60`. See [`power-button.md`](power-button.md) |
| DSM OS-parity tuning (2026-09-21) | **✅ APPLIED** — `somaxconn=65535`, `accept_ra_defrtr=0` (live), USB autosuspend **off** `-1` (live), SoC Orion watchdog `RuntimeWatchdogSec=60` (armed, effective next boot). RTC power-schedule tool `rtc-power-schedule.sh` installed (**not yet live-tested** — needs a box test). See [`dsm-os-features.md`](dsm-os-features.md) |
| MUST-1 udev | **PASS** — DTB no `alarm-gpios`; udev ~0.2% after settle; uevent 1779 idle |
| MUST-2 net | **PASS** — `.233` on `eth0:1` + DHCP `.77`; rgmii-id; networking + dhclient OK |
| MUST-3 data | **PASS** — `sda3` `/srv/data` rw,noatime |
| MUST-4 SMART | **PASS** — smartd drives bay amber only for SMART health/attribute failures |
| MUST-5 NTP | **PASS** — chrony synced; rtc-mv |
| MUST-6 zram | **PASS** — zram0 2 GiB lz4 prio 100; journal 50M |
| MUST-7 apt | **PASS** — trixie + updates + security; `apt-get update` OK this boot |
| MUST-8 samba | **skip** per owner |
| MUST-9 recovery | **PASS** — `list` live; TFTP default **`5ea71e0b…`** |
| MUST-10 cold boot | **PASS historical PSU cut**; **this session = `reboot` only** (no button → no `poweroff`) |
| MUST-11 MCU/LED | **PASS** — ping + this-boot begin/ready/beep; bay amber **off while SMART is healthy** |
| MUST-12 fan | **PASS on this boot** — wait-loop found hwmon ~6s; pwm never 0; 58 °C sticky at 145 |

`systemctl --failed`: **none**. `qnap_poweroff_ds115j` loaded. sda2 `uImage-ds115j` = `6b58d6eee97005845923167d5fe481035b7031195935bd632cdbe29ae75ed0f6` (USB VBUS fix DTB, 2026-09-20) — ramdisk unchanged `dbbd30ec…`. TFTP `/srv/tftp/uImage-ds115j` still `5ea71e0b…` (previous; promote when convenient).

**Daily-ready: YES** (scoped: no Samba/backups/nftables/burn-in).

## Reboot (11:58–12:00 UTC)

```text
pre-baseline  11:58:34 UTC  (boot 10:55, up 1h03)
reboot issued 11:58:57 UTC
ping lost     11:59:03 UTC
SSH .233      12:00:53 UTC  up 1 min; who -b 2026-09-16 11:59
systemd-analyze 7.667s kernel + 39.341s userspace = 47.008s
```

True PSU `poweroff` **not** run (would cut PSU with no one to press the front button). Owner step: at the chassis, `poweroff`, then front button.

## MUST-12 this boot (the wait-loop proof)

```text
11:59:46  syno-fan.service Started
11:59:52  using /sys/class/hwmon/hwmon1/pwm1
11:59:52  65°C  ->  pwm=190  fan1_target=1750
12:00:13  60°C  ->  pwm=145  fan1_target=1500
12:01:53  64°C  ->  pwm=190  fan1_target=1750   (apt-get update load)
12:02:13  60°C  ->  pwm=145  fan1_target=1500
```

Live sample **12:02:33–12:05:51 UTC** (12 polls): **pwm=145 / target=1500** at **58.0 °C**. Old pwm-delta hunt would have dropped to 110.

## Kernel / boot image

- Live/sda2/TFTP default: **`5ea71e0b…`** (6,060,176 B), no `alarm-gpios`.
- TFTP keep: `uImage-ds115j.pre-alarm-gpios-c1688fda` = `c1688fda…`.
- HANDOFF `artifacts/ds115j.dts` SHA `89bc51c8…` = live DTS (no alarm).

## Identity (boot 2026-09-16 11:59 UTC)

```text
hostname:     ds115j
uname:        Linux ds115j 6.12.107+deb13-armmp #1 SMP Debian 6.12.107-1 (2026-08-29) armv7l
os:           Debian GNU/Linux 13 (trixie)  13.7
cmdline:      console=ttyS0,115200 earlyprintk root=LABEL=rootfs rootwait rw panic=10
model:        Synology DS115j
RAM:          233 MiB; SwapTotal zram0 2G lz4 prio 100
```

## Disk / mounts

```text
sda1  64G  ext4  LABEL=rootfs  UUID=fc9ea304-14d5-4494-a117-7dfda838e18b  /
sda2 128M  ext2  LABEL=boot    UUID=eec9c4e3-7c83-40b6-af29-e28c4f228baa
sda3  1.8T ext4  LABEL=data    UUID=2fd25b2a-ceb7-4155-bde9-87dec3d66e2b  /srv/data  (rw,noatime)
```

## Networking

`.233/22` on `eth0:1` (permanent). DHCP `.77/22` on `eth0` this boot. `networking.service` OK. Cosmetic `Address already assigned`. Never restore `auto eth0:1`. Never `ifdown eth0` from the only SSH session. Live MAC `00:11:32:4d:c3:b8`. PHY rgmii-id, 88E1318S, 1G full.

## MCU / fan / LED

- `/usr/local/sbin/syno-mcu.sh ping` OK (`/dev/ttyS1`).
- **Power button:** `syno-powerbtn.service` + `syno-powerbtn-arm.service`
  (2026-09-21) — **armed and VERIFIED live**: `/etc/syno-powerbtn.conf`
  `TRIGGER_BYTES="30"`, `SETTLE_SEC=60`, `DEBOUNCE_SEC=30`. Press-and-hold ~2 s →
  PIC pushes **`0x30` (`'0'`)** → daemon logs `POWER BUTTON detected` → `systemctl
  poweroff` → `qnap_poweroff_ds115j.ko` cuts the PSU (clean hardware power-off).
  Proven: byte captured twice, armed press powered the box off twice, and the
  arming **survives power-off** (PIC standby rail; the arm unit re-sends the DSM
  rc bytes `echo 4`/`echo 9` defensively at boot). The daemon reads `/dev/ttyS1`
  **read-only** and never writes. Details + SPI-forensics proof that the button
  reaches Linux only via the PIC on UART1: [`power-button.md`](power-button.md).
  If the button ever stops working after a long wall-power loss, re-run
  `/usr/local/sbin/syno-powerbtn-arm.sh`.
- `syno-mcu-boot-begin.service` 11:59:35 blink + orange steady; `syno-mcu-boot.service` 12:00:06 ready + beep.
- `/usr/local/sbin/syno-fan.sh` + `syno-fan.service` (wait-loop proven this boot).
- Bay LED: `synology:amber:disk` **`trigger=none`, `brightness=0`** while healthy. smartd now runs `/usr/local/sbin/smart-amber-led.sh` for SMART health/attribute failures; `smart-amber-led.timer` reconciles every 15 minutes and clears recovered conditions. The 11:31 UTC `disk-activity` udev rule remains **removed**. Green is hardware SATA. See [`SMART-AMBER-LED.md`](SMART-AMBER-LED.md).

### LED map (front panel)

| LED | Driven by | First ~10–15 s | Boot (userspace) | Ready |
|---|---|---|---|---|
| Power (blue) | MCU UART1 `'4'/'5'/'6'` | MCU power-on default | **blink** `'5'` | **steady** `'4'` |
| Status (green/orange) | MCU UART1 `'7'…';'` | MCU power-on default | **orange steady** `':'` | **green steady** `'8'` + 1 short beep |
| Bay green | **hardware** SATA | green | green | green |
| Bay amber | Linux gpio-led MPP31 | off | off | off healthy; steady on for SMART failure |

Linux cannot drive the MCU before `/dev/ttyS1` exists, so U-Boot + kernel + ~4 s of userspace run on the **MCU's own default** pattern. Removing that window would need U-Boot env writes — **forbidden** (SPI landmine).

## Recovery

```text
/root/deploy-boot.sh /root list
/root/deploy-boot.sh /root dry-prev    # would restore c1688fda (alarm-gpios) — do not boot casually
```

## Safe re-check

```bash
ssh root@192.168.68.233
systemctl --failed
systemctl is-active syno-fan.service networking chrony
journalctl -u syno-fan.service -b --no-pager
sha256sum /srv/tftp/uImage-ds115j                 # helper: 5ea71e0b…
test -e /sys/firmware/devicetree/base/gpio-fan/alarm-gpios && echo BAD || echo ABSENT
```
