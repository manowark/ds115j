# SMART-only amber disk LED

Implemented 2026-09-16 on `root@192.168.68.233`.

## Behaviour

- Healthy: `/sys/class/leds/synology:amber:disk` has `trigger=[none]`,
  `brightness=0`.
- SMART overall health failure, a failing SMART usage attribute, pending
  sectors, or offline-uncorrectable sectors: amber is set steady on
  (`trigger=none`, `brightness=1`).
- `disk-activity`, `disk-read`, and `disk-write` are never selected.
- Bay green remains hardware-controlled by SATA link/activity.
- The fan and UART/MCU status LEDs are not accessed.

smartd calls `/usr/local/sbin/smart-amber-led.sh` immediately through:

```text
-m <nomailer> -M exec /usr/local/sbin/smart-amber-led.sh
```

`smart-amber-led.timer` also runs a read-only `smartctl -H -A /dev/sda`
reconciliation every 15 minutes. This clears amber after the health/attribute
condition recovers because smartd does not provide a general recovery hook.
If SMART cannot be read, the script preserves the current LED state.

## Installed files

```text
/usr/local/sbin/smart-amber-led.sh
/etc/systemd/system/smart-amber-led.service
/etc/systemd/system/smart-amber-led.timer
/etc/smartd.conf
/etc/smartd.conf.bak.pre-amber-led
```

Canonical helper copies:

```text
/root/ds115j/scripts/smart-amber-led.sh
/root/ds115j/scripts/smart-amber-led.service
/root/ds115j/scripts/smart-amber-led.timer
/root/ds115j/scripts/smartd.conf.ds115j
```

## Safe owner verification

No disk failure is forced:

```bash
/usr/local/sbin/smart-amber-led.sh fail    # steady amber on
/usr/local/sbin/smart-amber-led.sh status
/usr/local/sbin/smart-amber-led.sh ok      # amber off
/usr/local/sbin/smart-amber-led.sh check   # reconcile from real SMART data
journalctl -t smart-amber-led --no-pager -n 20
```

2026-09-16 proof: manual `fail` twice remained at brightness 1; `ok` twice
returned to 0; a simulated smartd `Health` event set brightness 1, and the
real PASSED health check cleared it to 0. A native smartd `-M test` invocation
called the hook successfully and intentionally left the LED unchanged.
Final state: `trigger=[none]`, `brightness=0`; smartd and the timer active.
