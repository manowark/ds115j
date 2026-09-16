# LED behaviour (DS115j)

## Map

| LED | Driven by | First ~10–15 s (MCU default) | Linux boot | Ready |
|-----|-----------|------------------------------|------------|-------|
| Power (blue) | MCU UART1 `'4'`/`'5'`/`'6'` | MCU power-on default | **blink** `'5'` | **steady** `'4'` |
| Status (green/orange) | MCU UART1 `'7'`…`';'` | MCU power-on default | **orange steady** `':'` | **green steady** `'8'` + one short beep |
| Bay green | **hardware** SATA | green | green | green |
| Bay amber | Linux gpio-led **MPP31** only | off | off | off if SMART healthy; **steady on** if SMART fail |

There is **no** Linux sysfs for the status LED. Scripts: [`../scripts/syno-mcu.sh`](../scripts/syno-mcu.sh), [`../scripts/syno-mcu-boot.sh`](../scripts/syno-mcu-boot.sh).

Linux cannot talk to the MCU until `/dev/ttyS1` exists, so U-Boot + early kernel stay on the MCU’s own pattern. Closing that window would need U-Boot env / SPI writes — **forbidden**.

## Bay amber

- Healthy: `trigger=none`, `brightness=0` (green SATA LED only).
- SMART health/attribute failure: amber **steady ON**. See [smart-amber-led.md](smart-amber-led.md).
- **Never** `disk-activity` on amber — the bay then blinks orange and hides the green LED. Optional udev rule is **not** installed (`scripts/disk-led-amber-activity.rules.optional-NOT-INSTALLED`).

## Owner test (MCU)

```bash
ssh root@192.168.68.233
/usr/local/sbin/syno-mcu.sh ping
/usr/local/sbin/syno-mcu.sh healthy
```

Do **not** send `'1'` (power-off) or `'C'` (reset) by hand. Kernel module `qnap_poweroff_ds115j` owns power-off.
