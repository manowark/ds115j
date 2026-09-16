# DS115j Debian install kit

Bring a **Synology DS115j** (Marvell Armada 370, 256 MiB RAM) to the same **Debian 13 (trixie) armhf daily-ready** state as the live box on this LAN, or **reinstall this one**.

This is a self-contained UART + TFTP + HDD kit. A fresh clone contains the
known-good boot artifacts and the complete Debian rootfs payload.

**For a complete helper-free daily-ready install or reinstall, follow only [docs/install-uart.md](docs/install-uart.md).**

## Daily-ready scope (2026-09-16)

HDD boot from `ide 0:2`, SSH, DHCP + permanent `.233`, RGMII Ethernet, MCU LEDs/beep, temperature fan, SMART → bay amber only on failure, zram, chrony, `qnap_poweroff_ds115j` PSU cut. Samba/backups/nftables are **out of scope**.

Live probe: [docs/current-state.md](docs/current-state.md). Cold-boot checklist: [docs/cold-boot-verify.md](docs/cold-boot-verify.md).

## Access (trusted LAN only)

| Role | Address | Login |
|------|---------|--------|
| NAS | `192.168.68.233/22` | `ssh root@192.168.68.233` password `ds115j` |
| Laptop (TFTP) | example `192.168.68.251/22` | run `scripts/serve-tftp.sh` from this clone |
| UART | `115200 8N1` | `screen /dev/cu.usbserial-BG01OOBA 115200` |

Full notes: [docs/access.md](docs/access.md).

## Current good boot files

Verify after copy:

```bash
cd boot && shasum -a 256 -c SHA256SUMS
```

| File | SHA-256 (full) | Role |
|------|----------------|------|
| `boot/uImage-ds115j` | `5ea71e0bc69a17ae269e278eedc28288702f1259edffefd97d420e01141ae3e8` | Kernel + **appended DTB, no `alarm-gpios`** |
| `boot/uRamdisk-hdd-ds115j` | `dbbd30ec2c3772e2816eaa5e3295b0580a357fc93458dcb3bf063bf7bf65cd75` | Initramfs → `LABEL=rootfs` |
| `boot/uRamdisk-recovery-ds115j` | `cc9e6bc063a1247c3f370a87238f6ff544ff01ba145aed19f537b13d2810dd96` | BusyBox recovery (fsck) |

Kernel / ramdisk / `modules/qnap-poweroff-ds115j.ko` are **one set**. Vermagic: `6.12.107+deb13-armmp`. Do not `apt upgrade` the kernel as a routine update.

Board DTS (good): `dts/ds115j.dts` SHA `89bc51c8…`. The file `dts/ds115j.dts.stale-with-alarm-gpios` is labelled **do not build**.

## Layout

```
docs/install-uart.md   NEW DEVICE + REINSTALL (manual UART)
docs/landmines.md      never ide 0:1, never casual saveenv, …
docs/recovery.md       TFTP / sda2 rollback
docs/led-behaviour.md
docs/smart-amber-led.md
docs/current-state.md
scripts/               MCU, fan, SMART amber, deploy-boot, bootstrap
dts/                   good DTS/DTB
boot/                  uImage + ramdisks
firmware/spi/          8 MiB SPI dump (unbrick reference; do not rewrite SPI)
modules/               qnap_poweroff_ds115j.ko + source
rootfs/                split Debian rootfs archive (<95 MB per Git object)
config/                interfaces, smartd, systemd examples from the live NAS
HANDOFF/               historical bring-up notes
```

## Landmines (read before any U-Boot)

- **Never** `ide 0:1` (hangs). Boot files live on **`ide 0:2`** (`sda2`).
- **Never** casual `saveenv` / `sf write` / `bubt` / `fw_setenv` (env sits inside stock zImage in SPI).
- Do not run `scripts/extract-hdd.sh` on the **live** NAS — it wipes `/dev/sda` and is a **stale single-partition** recipe.
- Do not attach `disk-activity` to the bay amber LED.

Full list: [docs/landmines.md](docs/landmines.md).

## Rootfs included in git

GitHub rejects individual files over 100 MB, so the 134,385,614-byte archive
is committed as two ordinary Git files:

| File | Bytes | SHA-256 |
|---|---:|---|
| `rootfs/rootfs-trixie-armhf.tar.gz.part-aa` | 94,371,840 | `4aa9576e09e41004156dafaa488819413f21240a5ec137869597566f8e35f9b3` |
| `rootfs/rootfs-trixie-armhf.tar.gz.part-ab` | 40,013,774 | `d224d7238803be805a440f27f339c012146beac492808bdaa4b9c51d279b744d` |

Reconstruct and verify the original archive:

```bash
scripts/reconstruct-rootfs.sh
# rootfs-trixie-armhf.tar.gz SHA-256:
# 9d869bf8f45f6f3908097aece847bb2d1bde4a6213801cb8460cdb83f9a30eb6
```

No Git LFS client or helper host is required. To rebuild from Debian mirrors
instead, a Linux machine with `mmdebstrap` can run
`sudo scripts/bootstrap-rootfs.sh`.

First-boot `dpkg --configure -a` and `apt-get` **need Internet on the NAS**.

## Laptop serving

Give the laptop a LAN address such as `192.168.68.251/22`, then run:

```bash
scripts/serve-tftp.sh
```

The script stages and serves the three files in `boot/`. The former Raspberry
Pi helper is historical and optional; installation and recovery do not use it.
