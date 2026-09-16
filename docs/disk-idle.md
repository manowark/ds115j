# HDD spin-down (10 minutes idle)

Idle SATA standby on the DS115j so the WD Red can park after **10 minutes**
without I/O. Fan PWM, MCU UART1, SPI, and U-Boot env are not touched.

`hdparm -S 120` is **120 × 5 s = 600 s**.

## What is installed

| Piece | Path | Role |
|-------|------|------|
| `hdparm` | Debian package | Set ATA standby timer |
| `disk-idle.service` | oneshot after `multi-user.target` | `hdparm -S 120 /dev/sda` at boot |
| smartd | `/etc/smartd.conf` | `-n standby,q` plus existing `-M exec` amber hook |
| smartd interval | `/etc/default/smartmontools` | `--interval=3600` (was 1800) |
| SMART amber timer | `smart-amber-led.timer` | `OnUnitActiveSec=1h` (was 15min) so the disk can sleep |
| journald | drop-in `ds115j.conf` | `Storage=volatile`, `RuntimeMaxUse=50M` |
| root fstab | `LABEL=rootfs` | `noatime,commit=60` |

Logs in the journal **do not survive reboot**. That is intentional: persistent
journal writes keep a 256 MiB NAS disk awake.

## Apply

On a running NAS, from this repository (or the install kit):

```sh
sh scripts/install-disk-idle.sh
```

`scripts/install-userspace.sh` calls the same script. It never runs
`ifdown eth0`, never unbinds `gpio-fan`, never talks to the MCU, and never
writes SPI.

## Sample snippets (live-shaped)

smartd device line (keep the amber `-M exec`):

```text
/dev/sda -d sat -n standby,q -a -o on -S on -s (S/../.././02|L/../../6/03) -W 4,45,50 -m <nomailer> -M exec /usr/local/sbin/smart-amber-led.sh
```

journald drop-in `/etc/systemd/journald.conf.d/ds115j.conf`:

```ini
[Journal]
Storage=volatile
RuntimeMaxUse=50M
```

root fstab (backup `/etc/fstab` first; do not rewrite `sda` letters):

```text
LABEL=rootfs	/	ext4	errors=remount-ro,noatime,commit=60	0	1
```

Canonical copies: `config/smartd.conf`, `config/journald.conf`,
`config/fstab`, `config/smartmontools`, `scripts/disk-idle.service`.

## Load_Cycle_Count

WD Red parks heads on standby. Each sleep/wake increments SMART
**Load_Cycle_Count** (and often Start_Stop_Count). A 10-minute idle timer
will raise those counters on a quiet NAS; that is expected.

Do **not** add `hdparm -B` (APM). Aggressive APM on WD Green/Red historically
ran LCC up in days. This kit only sets the standby timer (`-S 120`).

Live WD20EFRX (2026-09-16, before this change) already showed LCC in the
low 20k range with Start_Stop_Count similar. Typical design ratings are
hundreds of thousands of load cycles; watch the attribute if the box is
flapping in and out of standby.

## Verify

Immediately after install the disk should still be awake:

```sh
systemctl is-active disk-idle.service    # active
hdparm -C /dev/sda                       # drive state is: active/idle
findmnt -o OPTIONS /                     # includes noatime,commit=60
```

After **10+ minutes** with no SSH/apt/SMART/journal traffic to the disk:

```sh
hdparm -C /dev/sda                       # drive state is: standby
```

`hdparm -C` itself does not spin the drive up. A later `smartctl -A` or
writing a file **will**. Do not run `hdparm -y` just to demo sleep unless
you are prepared for a spin-up on the next I/O.

## Landmines (this change)

- Never `ide 0:1`, `ifdown eth0`, unbind `gpio-fan`, SPI/`saveenv`, or wipe
  partitions.
- Do not set the fan to PWM 0.
- Prefer `.233` (`eth0:1`) so DHCP changes do not drop SSH.
