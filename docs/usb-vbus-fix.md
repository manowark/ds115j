# USB VBUS FIX + POWER-BUTTON FINDING — DS115j (2026-09-20)

Result of the "no 5 V on either USB port" investigation and the power-button
question ("може це якось пов'язано з пінами").

## Verdict

1. **USB is FIXED, root cause was in the DTB.** Both ports now deliver 5 V and
   enumerate devices with the standard kernel.
2. **Power button is NOT related to the pins.** It was never wired to power off
   under this Debian; it is a pre-existing gap (missing ttyS1 daemon). Nothing
   in this session's GPIO work touched the button's power path.

---

## USB root cause

The DS115j gates USB VBUS behind a load switch driven from **MPP44** (= `gpio1`
pin 12 = global GPIO 44), where **5 V is on when the line is LOW**. The
manowark DTS has no node for this switch, so nothing ever pulls the pin low:

- no VBUS on either port → flash LED stays dark, D+ never pulls up;
- EHCI controllers themselves are healthy: `f1050000/f1051000`, 1 port each,
  PORTSC `c501000 … POWER sig=se0`, IRQs 42/43 always 0 (no connect events).

Source: community DS115j DTS by "deelan" (Doozan forum, via Wayback Machine),
derived from Synology GPL board sources ("DS115j GPIO Init" in the DSM boot
log). It declares `usb_regulator` on MPP44, enable-active-low, always-on;
the manowark DTS simply lacks this node.

### Live proof (before any boot image change)

Driving GPIO 44 LOW via sysfs for ~5 s with the flash inserted:

```text
t+0s: usb1=configured      # front port went live
usb1: Phison Flash Drive 2 GB [ICIDU] (13fe:1e00)
usb2: Ugreen ASM1153 SATA bridge (174c:1153)   # rear port too
```

So **one pin gates BOTH ports** — exactly the load-switch design.

## The fix (deployed, verified)

Added to the DTB (round-trip: decompile `base.dtb` → edit → recompile with
`dtc`; the plain round trip is byte-identical `56003d33…`):

```dts
regulators {
    compatible = "simple-bus";
    #address-cells = <1>;
    #size-cells = <0>;

    usb_regulator: usb-regulator@2 {
        compatible = "regulator-fixed";
        regulator-name = "USB Power";
        regulator-min-microvolt = <5000000>;
        regulator-max-microvolt = <5000000>;
        regulator-always-on;
        regulator-boot-on;
        gpio = <&gpio1 12 GPIO_ACTIVE_LOW>;
    };
};
```

Verified against `fixed.c` v6.12: `regulator-boot-on` → `GPIOD_OUT_HIGH` on
request, and *"the signal will be inverted by the GPIO core if flagged so in
the descriptor"* → physical LOW = VBUS on. `gpio-44 (regulators:usb-regul)
out lo` confirmed live.

### Trap avoided (dmesg)

First attempt added a pinctrl pin node `usb-pwr-pin { marvell,pins="mpp44";
marvell,function="gpio"; }` plus `pinctrl-0 = <&usb_pwr_pin>`. It failed:

```text
armada-370-pinctrl f1018000.pin-ctrl: unsupported function gpio on pin mpp44
pinctrl core: failed to register map default (0): invalid type given
```

The Armada 370 **pinctrl has no `gpio` function for mpp44** (it is already in
GPIO mode by default), so the pinctrl map registration failed and the
regulator probe never happened. **Removed the pinctrl node — regulator probes
cleanly with no pinctrl.** (Checked the box on the NAS: pin 44 already shows
`12:f1018140.gpio` mux by default.)

### Deployment

- New uImage = identical kernel zImage + new appended DTB (14 258 B, up from
  13 904 B).
- Deployed via `/root/deploy-boot.sh` to **sda2 only**; previous pair kept as
  `uImage-ds115j.pre-20260920-205106`; read-back sha256 verified before
  umount. Ramdisk untouched (`dbbd30ec…`).
- Rollback if ever needed: `/root/deploy-boot.sh prev` (+ reboot).

Post-reboot evidence:

```text
/sys/class/regulator/regulator.1: USB Power
gpio-44  (regulators:usb-regul) out lo
lsusb: 13fe:1e00 (flash, usb1) + 174c:1153 (ASMedia, usb2)
usb1-port1: configured ; /dev/sdb 1.9G read 1 MiB at 9.3 MB/s
```

Repo DTB: `dts/ds115j.dtb` sha `a698ce3e…` == DTB appended in the live uImage
on sda2.

---

## Power button finding (unrelated to pins)

- The power button only powers the box **ON** (after a PSU cut) — it never
  powered it OFF under this Debian.
- In DSM the MCU (PIC16LF1828 on ttyS1) handles power events and the front
  status LEDs. Under this Debian there is **no ttyS1 daemon**, so the MCU's
  button/remote events are unhandled (checked: no button-handler service, no
  ttyS1 reader). Linux does a controlled `poweroff` of its own accord, then
  `qnap_poweroff_ds115j` cuts the PSU on shutdown — independent of the button.
- MUST-10 cold-boot doc already reflects this: button = power on after PSU cut;
  `poweroff` = via SSH. This session's GPIO scans did not touch the button path
  (MCU pins were never exported; landmines still prohibit `'1'`/`'C'` on ttyS1).

### Optional follow-up (not done)

A tiny systemd daemon could listen on ttyS1 and run `poweroff` on the MCU's
remote/button power-off event (MCU power-off command would remove the PSU cut
race). Not implemented — out of scope for this session.