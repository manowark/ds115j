# POWER BUTTON — DS115j front power-button daemon (2026-09-21)

**Status: ✅ FULLY WORKING — verified live 2026-09-21.** The front power button now
performs a clean `poweroff` on Debian 13 (armv7l). Complete verified chain:

```
press-and-hold ~2 s → PIC16LF1828 pushes 0x30 on /dev/ttyS1 (9600 8N1)
→ syno-powerbtn (ARMED, TRIGGER_BYTES="30") logs "POWER BUTTON detected"
→ sleep 2 → systemctl poweroff → qnap-poweroff-ds115j.ko poweroff-notifier
→ PIC cuts PSU → hardware power-off confirmed on the box
```

Live evidence (all at the box, 2026-09-21):
- 11:18:00 — `byte 0x30` on **first** press (after sending the rc boot bytes,
  see below) — first PIC→host byte ever seen under Debian.
- 11:19:32 — `byte 0x30` again on a **second** press (repeatability confirmed).
- ~11:21 — armed to `TRIGGER_BYTES="30"`, press → **clean hardware power-off.**

**Arming requirement (H1 — CONFIRMED):** the PIC reports the button only after the
host sends the DSM rc boot bytes with a trailing newline — `echo 4 > /dev/ttyS1`
(`0x34 0x0A`, power LED on) then `echo 9 > /dev/ttyS1` (`0x39 0x0A`, status/LED state).
These exact newline-terminated writes exist in DSM's `/etc/rc`
(`SupportLedBehaviorV2` branch); Debian's syno-mcu had sent the same *bare* bytes
(no `\n`) which the LED visibly executed but which did **not** arm button reporting.
Only after the newline-form writes did the PIC start pushing `0x30`.
(The earlier live press @07:19 UTC — before any rc-bytes replication — produced
0 bytes.)

**Falsified along the way (no button press needed):**
- ~~**"PIC pushes spontaneously with zero init"**~~ — falsified by the 07:19 press
  giving 0 bytes while the daemon had never sent the rc boot bytes.
- ~~**O_RDWR open-mode hold (scemd's 0x902)**~~ — falsified 2026-09-21 by a live
  TIOCMGET (`scripts/ttymode-diag.pl`): O_RDONLY vs O_RDWR|O_NOCTTY|O_NONBLOCK vs
  O_RDWR|O_NOCTTY all report identical `TIOCM=0x4146` (DTR, RTS, CD, DSR asserted),
  so a read-only daemon already holds the modem lines exactly like scemd.
- ~~**`syno_led_mask_on` boot step writes a ttyS1 byte**~~ — resolved: it issues
  ioctl `SYNOIO_LED_DISK_MASK` (`0xc0104b0a`) which dispatches through the synobios
  service table to disk-LED functions (`set_disk_led_one`/`SetDiskLedStatus`/
  `funcSYNOSATADiskLedCtrl`) that drive SoC GPIO / SATA-chip registers
  (`SYNO_SOC_HDD_LED_SET`) — never `syno_ttyS_write`. synobios is rmmod'd right
  after in rc, so the **only host→PIC bytes in all of DSM boot+runtime are rc's
  `echo 4`/`echo 9`**.

Live test kit (button press required, at the box) is below under
[Verification](#verification-when-you-are-at-the-box).

## Context

On the DS115j the front power button is wired to the **PIC16LF1828** (MCU on
UART1 `/dev/ttyS1`, 9600 8N1), not to a SoC GPIO:

- Button powers the box **on** after a PSU cut (verified: pure PIC/PSU path, no software).
- In DSM, a press while running = graceful shutdown request to Linux.
- This Debian had **no handler** on the button (shutdown only via SSH), because DSM's
  handler lives in DSM userspace + the `synobios` kernel module — neither runs here.

## How the button channel was proven (SPI forensics)

Source: the verified 8 MiB SPI dump `firmware/spi/ds115j-spi-8m-20260915-124830.bin`
(sha256 `cfbdc0dd…`), which contains the vendor DSM image (`bootm 0xf40c0000 0xf4390000`).

1. `0x0c0000` = uImage kernel zImage (Linux 3.2.101) → **LZMA** decompressed.
2. `0x390000` = uImage ramdisk (type Multi) → LZMA-alone → 24 MiB **ext2** image
   = the DSM rd rootfs → extracted with `firmware/spi/ext2read.py`.
3. Only platform module = `usr/lib/modules/synobios.ko` (73 KB).
   - `mv_level_button.c` (GPIO-IRQ "level button", `request_threaded_irq`,
     "power button pressed") is **dead code for DS115j** — zero relocations /
     pointer references to `level_button_init`/`level_button_exit`. GPIO buttons
     are **not** wired on this model (that path serves other Armada boards).
   - The MCU channel is **UART1**: `syno_ttyS_read` (kernel_read, 250 ms inter-byte
     timeout, 5 retries), `syno_ttyS_set_termios`, `save_char_from_uart`,
     `save_current_data_from_uart`, `current_tty_buf` (raw MCU bytes, hex `%.2x`).
   - DSM's userland peers with the PIC through `synobios_ioctl` (read/write-and-read
     wrappers) — polling happens in DSM userspace, not in the kernel.

Bottom line: **"power button pressed" reaches Linux only via the PIC → ttyS1 → a
daemon.** The async-vs-poll question is now answered from the DSM binary (below):
the PIC **pushes** the byte; scemd only waits on `select()`. Live press #1 still
confirms the byte value on this box before arming.

## Protocol, from the DSM binary

Source: `ds115j-usb-build/hda1-rootfs/usr/syno/bin/scemd` (from the SPI dump's DSM
rootfs). Symbols resolved via the ELF dynamic relocation table.

### Reader side — how the byte arrives (hw_polling.c)

`hw_polling` thread (`0x41608`) opens `/dev/ttyS1` (`open64`, 12 retries) and
`/dev/ttyACM0` (`SupportLCM` gate, 30 retries), then loops on `select()` over the two
fds (+ an OpenBiosDev fd). **No request byte is ever sent before reading.**

```text
41934 ttyACM0 readable -> fcntl(O_NONBLOCK) -> SLIBCRead 1B -> enqueue(key=27) -> send 'S'(0x53)
41a0c ttyS1  readable -> SLIBCRead 1B        -> enqueue(key=4)  -> send 0x02
```

The polling loop `0x214fc` then does `dequeue(key=4)`; when size==1 it loads the byte
and calls the dispatcher `0x21020`. So a raw 1-byte event that lands on ttyS1 is
forwarded untouched. There is **no poll/arm byte in scemd** — but note: the PIC
still needs the *rc boot-time* host writes (`echo 4`, `echo 9`) before it starts
reporting (proven live 2026-09-21, see header).

### Dispatcher byte map (event_microp.c)

`0x21020(byte)` — matches the PIC byte, replies as follows. **Important:** in DSM the
replies do **not** go straight to ttyS1 — they are sent via a UNIX datagram socket
`/tmp/scemd_event_handler.sock_server` (verified `socket(AF_UNIX)` + `sendto` in
`0x456bc`) to the module's event handler, which relays them to the PIC. That path
does not exist in bare Debian (no `synobios.ko`) — which is exactly why our daemon is
**read-only** and powers off Linux itself; it never needs to answer the PIC.

| PIC byte | Meaning (log line) | scemd reply |
|---|---|---|
| **`'0'` 0x30** | **power button pressed** (`0x49b84`) | **7** |
| `'a'` 0x61 | reset button pressed (`0x49bf4`) | 8 |
| `` ` `` 0x60 | usbcopy/mute (`0x49c18`; needs `(byte&3)==1`) | 39 |
| `'f'` 0x66 | plus a 12-byte cmd-23 push (`0x465c8`) | 9 |
| `'g'` 0x67 | — | 49 (`'1'` — scemd's *reply*, safe only as a reply) |

Strings proven in place: `power button pressed, ret = 0` @ `0x49b84`,
`reset button pressed, ret = 0` @ `0x49bf4`, `usbcopy button pressed, ret = 0` @
`0x49c18`, `reset_button_disable` @ `0x49bbc`, `%s:%d message size of %d is not match
char!!` @ `0x49c70`.

### What this means for the daemon

- The **power button byte is `0x30`** and it is **spontaneous** (select-based reader,
  no request). `TRIGGER_BYTES="30"` is the arm value.
- The `'1'`/`'C'` landmine notes stand: `'1'` is a *reply* scemd issues to `'g'`
  (0x67); we never send anything, so no conflict.
- No byte needs to be written to observe the press. The reply bytes (2/7/etc.) are
  DSM's job and are irrelevant to a clean `poweroff`.

## What was deployed (NAS)

| File | Purpose |
|---|---|
| `/usr/local/sbin/syno-powerbtn.sh` | read-only daemon on `/dev/ttyS1` |
| `/etc/syno-powerbtn.conf` | trigger config (empty = observe mode) |
| `/etc/systemd/system/syno-powerbtn.service` | systemd unit, enabled |

Canonical copies live in the repo under [`scripts/`](../scripts/).

**Safety properties**
- Opens `/dev/ttyS1` **read-only** (`exec 3<`, verified `lr-x` in `/proc/PID/fd`).
- **Never writes a byte** → landmines preserved (no `'1'`, no `'C'`, no requests).
- Idle MCU is silent → observer logs nothing between events (verified, 0 bytes in 20 s).
- Triggers **only** on bytes configured in `TRIGGER_BYTES` and only after a 60 s
  settle window, with 30 s debounce. Default `TRIGGER_BYTES=""` ⇒ no poweroff possible.

## Operation

```bash
ssh root@192.168.68.233
systemctl status syno-powerbtn        # active
journalctl -u syno-powerbtn -f        # live byte log from the PIC
```

Every byte the PIC sends is logged as `byte 0xNN`; consecutive bytes (gap ≤ 1 s) are
grouped into `MCU sequence: NN MM …` lines.

## Verification — ✅ DONE at the box 2026-09-21

The full chain was verified live (see header): two `byte 0x30` press confirmations,
then arming `TRIGGER_BYTES="30"` → clean hardware power-off. **If you ever need to
re-prove it after a reinstall**, the exact steps that worked:

1. Daemon in OBSERVE mode: `systemctl is-active syno-powerbtn`, then
   `journalctl -u syno-powerbtn -f`.
2. **Arming (required!) — send the DSM rc boot bytes once, newline-form:**
   ```bash
   ssh root@192.168.68.233 'echo 4 > /dev/ttyS1; sleep 1; echo 9 > /dev/ttyS1'
   ```
   (0x34 0x0A + 0x39 0x0A; the blue LED starts blinking — expected, that is the PIC
   executing 0x39's state).
3. Press-and-hold the front button ~2 s → journal shows `byte 0x30`.
4. Arm: `sed -i 's/^TRIGGER_BYTES=.*/TRIGGER_BYTES="30"/' /etc/syno-powerbtn.conf` +
   `systemctl restart syno-powerbtn` → log must say `ARMED, trigger byte(s): 30`.
5. Press-and-hold again → `POWER BUTTON detected (byte 0x30) — poweroff in 2s` →
   clean PSU cut via `qnap_poweroff_ds115j.ko`.

**Persistence — PROVEN 2026-09-21:** after the clean power-off, the NAS was
booted again with **no** rc bytes re-sent, and the very first press powered it
off cleanly again. The PIC keeps its armed state across a soft power-off
(`qnap_poweroff_ds115j` cuts the main PSU rail, but the PIC lives on a
standby rail that stays up — it is the unit that powers the box back on).
No reboot re-arming is needed.

Still, `scripts/syno-powerbtn-arm.sh` + `syno-powerbtn-arm.service` are
installed and enabled (idempotent, only the two OEM LED-init bytes): they cover
the one untested corner where the PIC could lose its latched state — a full
**wall-power loss long enough to drain its standby rail** (unplug/storm/PSU
brick always requires a *long* blackout before arguing about it; if the box
ever boots with the button dead, re-run the arm unit and it is fixed).

Notes:
- Per the DSM binary the press byte is **`0x30`** (event_microp.c, `'0'` = power
  button pressed), confirmed empirically. A multi-byte press sequence can be armed
  as `TRIGGER_BYTES="30 30"` (any byte in the set triggers).
- If a tested arming byte ever fires spuriously (e.g. the rear reset button shares
  it), revert to `TRIGGER_BYTES=""` and record the difference — tell me.
- The daemon stops itself on shutdown (`KillMode=control-group`, SIGTERM trap), so it
  never races the kernel power-off module for UART1.

## Landmines recap

- The daemon **reads only**; human operators must keep not sending `'1'`/`'C'` to the
  PIC, and never guess a poll byte on the live box.
- No SPI writes, no `ide 0:1`, sda2-only boot deploys — unchanged (see
  [`landmines.md`](landmines.md)).