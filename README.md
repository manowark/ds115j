# DS115j Debian install kit

Bring a **Synology DS115j** (Marvell Armada 370, 256 MiB RAM) to the same **Debian 13 (trixie) armhf daily-ready** state as the live box on this LAN, or **reinstall this one**.

This is a practical UART + TFTP + HDD kit. It is **not** a dump of the helper’s linux tree, DSM extracts, or build history.

**Start here for a new box or a wipe/reinstall:** [docs/install-uart.md](docs/install-uart.md)

## Daily-ready scope (2026-09-16)

HDD boot from `ide 0:2`, SSH, DHCP + permanent `.233`, RGMII Ethernet, MCU LEDs/beep, temperature fan, SMART → bay amber only on failure, zram, chrony, `qnap_poweroff_ds115j` PSU cut. Samba/backups/nftables are **out of scope**.

Live probe: [docs/current-state.md](docs/current-state.md). Cold-boot checklist: [docs/cold-boot-verify.md](docs/cold-boot-verify.md).

## Access (trusted LAN only)

| Role | Address | Login |
|------|---------|--------|
| NAS | `192.168.68.233/22` | `ssh root@192.168.68.233` password `ds115j` |
| Helper (TFTP/HTTP) | `192.168.68.250/22` | `ssh root@192.168.68.250` password `ds115j` |
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
config/                interfaces, smartd, systemd examples from the live NAS
HANDOFF/               curated helper docs (same facts, more history)
```

## Landmines (read before any U-Boot)

- **Never** `ide 0:1` (hangs). Boot files live on **`ide 0:2`** (`sda2`).
- **Never** casual `saveenv` / `sf write` / `bubt` / `fw_setenv` (env sits inside stock zImage in SPI).
- Do not run `scripts/extract-hdd.sh` on the **live** NAS — it wipes `/dev/sda` and is a **stale single-partition** recipe.
- Do not attach `disk-activity` to the bay amber LED.

Full list: [docs/landmines.md](docs/landmines.md).

## What is not in git

- Full Debian rootfs tarball (`rootfs-trixie-armhf.tar.gz` ~134 MiB, over GitHub’s ~100 MiB file limit). Build it on the helper with `scripts/bootstrap-rootfs.sh` or fetch from helper HTTP `:45152` if that service is running.
- Debian `linux-image` module tree (install on-device from apt **matching** `6.12.107+deb13-armmp`, or copy from the helper).
- The helper’s `linux/` git tree.

First-boot `dpkg --configure -a` and `apt-get` **need Internet on the NAS**.

## Helper vs this repo

The Raspberry Pi helper still holds the large build tree at `/root/ds115j` and live TFTP at `/srv/tftp`. This GitHub repo is the portable install kit. Prefer copying images **from this repo or helper TFTP**; do not wipe live `sda1`/`sda2` while testing.
