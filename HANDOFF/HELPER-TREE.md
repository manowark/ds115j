# HELPER-TREE — `/root/ds115j` and `/srv/tftp`

> Historical inventory only. Nothing here is required or authoritative for a
> reinstall. The Git repository now contains the rootfs parts and all supported
> boot/config/module artifacts.

Inventory **2026-09-15 19:51 UTC** on helper hostname `rpi` (`192.168.68.250`). HANDOFF copies are under `/root/ds115j/HANDOFF/artifacts/` (see `artifacts/MANIFEST.txt`).

This helper is **not a git repo**. Nested `linux/` is dirty and only a DTS/dtc aid.

## Disk usage (approx)

| Path | Size | Role |
|---|---:|---|
| `/root/ds115j` | **3.0 GiB** | entire project tree (includes HANDOFF) |
| `linux/` | 2.3 GiB | mainline `587858367-dirty` for dtc |
| `rootfs/` | 284 MiB | unpacked trixie armhf staging (may lag live NAS) |
| `kernel/` | 139 MiB | Debian kernel extract + **stale** uImage |
| `rootfs-trixie-armhf.tar.gz` | 129 MiB (`du`); **134,385,614** bytes | initial extract payload |
| `linux-image-6.12.107+deb13-armmp_6.12.107-1_armhf.deb` | 54 MiB | Debian kernel .deb |
| `/root/ds115j/HANDOFF/` | ~42+ MiB | this package |
| `backups/` | 31 MiB | DTS/uImage history + SPI |
| `/srv/tftp` | 33 MiB | **authoritative recovery images** |
| `artifacts/` | 18 MiB | final power-off/I2C build outputs |
| `initramfs-hdd/` | 7.0 MiB | HDD-root cpio tree |
| `initramfs/` | 6.9 MiB | recovery cpio tree |
| `_stock-vmlinux.bin.extracted/` | 6.7 MiB | stock analysis |
| `build-headers/` | 6.6 MiB | exact Debian ARM headers |
| `vmlinux.raw` | 4.9 MiB | stock analysis |
| `qnap-poweroff-module/` | 488 KiB | source + `.ko` |
| `scripts/` | 52 KiB | helper/recovery scripts; **`deploy-boot.sh`** (versioned boot deploy/rollback, canonical copy) |
| `HANDOFF/RECOVERY-RUNBOOK.md` | — | **operator recovery runbook** (scenarios A–F, boot-image inventory + hashes) |
| `spi-dumps` | symlink | → `backups/spi` |

## Critical hashes (live paths)

### SPI

| File | Bytes | SHA-256 |
|---|---:|---|
| `/root/ds115j/backups/spi/ds115j-spi-8m-20260915-124830.bin` | 8388608 | `cfbdc0dd57e3949957dbab23eb6befe84112fc36ed3b8a4e142c9ad78239dfc4` |
| `/root/ds115j/backups/spi/ds115j-vendor-20260915-124844.bin` | 65536 | `9cc6345f4a694d492b6aa4142198bf389d2ebfd63bbe964b09d2e70dd635daad` |

### DTS / DTB / module

| File | Bytes | SHA-256 | Notes |
|---|---:|---|---|
| `linux/arch/arm/boot/dts/marvell/ds115j.dts` | 4754 | `89bc51c826f34a2af9c24201745e58993d3f045479ea081fe4e586fb09d951e6` | **current** (no `alarm-gpios`) |
| `linux/arch/arm/boot/dts/marvell/ds115j.dtb` | 13904 | `56003d33dc836fea5de3de52eed6bf35681e3d04153e120b63657572f4d87d85` | rebuilt for new-noalarm |
| `artifacts/uImage-ds115j.new-noalarm` | **6060176** | **`5ea71e0bc69a17ae269e278eedc28288702f1259edffefd97d420e01141ae3e8`** | **current kernel+DTB (deployed to sda2 2026-09-16)** |
| `artifacts/kernel-ds115j-noalarm.bin` | 6060112 | `dd7d739877178a943103f2b270a402afb0f1b9ab8c31378083f24e34e802ed31` | uImage payload |
| `artifacts/uImage-ds115j` | 6060232 | `c1688fda…` | previous (still has `alarm-gpios`) |
| `artifacts/ds115j-poweroff-i2c.dtb` | 13960 | `cf192fe773…` | still has `alarm-gpios` |
| HANDOFF `artifacts/ds115j.dts` | 4754 | `89bc51c826f34a2af9c24201745e58993d3f045479ea081fe4e586fb09d951e6` | **synced 2026-09-16** (no `alarm-gpios`) |
| HANDOFF `artifacts/ds115j.dts.stale-with-alarm-gpios` | — | `8492da22688f65840a664e72f6aabd18426d2e1514d9437ef7187a74ad6bcb79` | old HANDOFF copy |
| `qnap-poweroff-module/qnap-poweroff-ds115j.ko` | 139524 | `3354e4fb61ecb21afcdb09e80180e152d9b2a3313e97f1394db6cef79312b053` | |
| `artifacts/zImage-6.12.107-armmp` | 6046208 | `b508abca3127cb0d9e1b3aba37f400cbd7dac170040641756807e0e496039de8` | identical in old + new uImage |

### `/srv/tftp` (complete)

| File | Bytes | SHA-256 | Notes |
|---|---:|---|---|
| **uImage-ds115j** | **6060176** | **`5ea71e0bc69a17ae269e278eedc28288702f1259edffefd97d420e01141ae3e8`** | **TFTP default = live sda2** (no `alarm-gpios`); promoted 2026-09-16 11:31 UTC |
| **uImage-ds115j.new-noalarm** | **6060176** | same as above | alias |
| uImage-ds115j.pre-alarm-gpios-c1688fda | 6060232 | `c1688fda25f1472d4b7b5b65b5ecc2a4d7b8a780cd9d6bb26c7c7df92d1c6a23` | previous TFTP default |
| uImage-ds115j.pre-noalarm-20260916 | 6060232 | `c1688fda…` | same bytes |
| uImage-ds115j.pre-poweroff-i2c-20260915-1638 | 6060240 | `69e60698a993b487f131c0b5120a960643b43fe46d6e5aee7d779908ee425bbc` | older |
| uImage-ds115j.with-unbound-rtc68-20260915 | 6060292 | `268eebcce70e1ace470f97e0a766a9f3f806c77c9bbd749d82015c521f7c0ee4` | false RTC node |
| uImage-nodtb | 6046272 | `64477b3dfeedb95b166bfae958405ef68c002e36e89c1a760f1f14762e5fc7ea` | **do not boot** |
| **uRamdisk-hdd-ds115j** | **3300604** | **`dbbd30ec2c3772e2816eaa5e3295b0580a357fc93458dcb3bf063bf7bf65cd75`** | HDD root |
| uRamdisk-recovery-ds115j | 3247969 | `cc9e6bc063a1247c3f370a87238f6ff544ff01ba145aed19f537b13d2810dd96` | BusyBox recovery |
| uRamdisk-ds115j | 3247969 | same as recovery | alias |
| ds115j-poweroff-i2c.dtb | 13960 | `cf192fe77338447a2f9949bf9640efe0b77c5cf7316d680a873057c5d4e3914b` | |
| qnap-poweroff-ds115j.ko | 139524 | `3354e4fb61ecb21afcdb09e80180e152d9b2a3313e97f1394db6cef79312b053` | |
| e2fsck | 276420 | `7d7a43efd6792560066ecf9971c5bfb98473abd1e4ec8dc66fd80b2175541a23` | ARM recovery |
| resize2fs | 67116 | `301f532e7ddd1fcc446129f800a48ee87f09ea8975a1e4fad3e4858349268ae6` | ARM recovery |

`file` on current uImage: U-Boot legacy, name `Debian 6.12.107 DS115j I2C`, load/entry `0x00008000`.

### Copy drift (important)

```text
NEW CURRENT (sda2, TFTP `uImage-ds115j`, TFTP `uImage-ds115j.new-noalarm`, live NAS):
  6060176  5ea71e0bc69a17ae269e278eedc28288702f1259edffefd97d420e01141ae3e8

PREVIOUS (TFTP `uImage-ds115j.pre-alarm-gpios-c1688fda`, sda2 `.pre-noalarm-20260916`, helper artifacts/uImage-ds115j):
  6060232  c1688fda25f1472d4b7b5b65b5ecc2a4d7b8a780cd9d6bb26c7c7df92d1c6a23

VERY OLD (kernel/uImage-ds115j, older rootfs/boot — also in sda2 as .pre-poweroff-i2c):
  6060240  69e60698a993b487f131c0b5120a960643b43fe46d6e5aee7d779908ee425bbc
```

TFTP default `uImage-ds115j` is **`5ea71e0b…`** (same as live sda2). Previous `c1688fda…` is versioned as `uImage-ds115j.pre-alarm-gpios-c1688fda`.

Rootfs tarball SHA-256 (from prior inventory): `9d869bf8f45f6f3908097aece847bb2d1bde4a6213801cb8460cdb83f9a30eb6`.

## Scripts (`/root/ds115j/scripts`)

| Script | Danger |
|---|---|
| `bootstrap-rootfs.sh` | helper-side only |
| `configure-rootfs.sh` | overlay; **static-era network** — can regress live DHCP |
| `fix-hdd-root.sh` | repairs mounted target; same static-era network risk |
| `extract-hdd.sh` | **DESTROYS /dev/sda** |
| `dump-spi-linux.sh` | read MTD |
| `recv-spi.sh` / `spi-recv-daemon.py` | TCP 45151 |
| `harvest-tftp-spi.sh` | move TFTP WRQ dump |
| `prep-ramdisk-hdd-tools.sh` | ramdisk tools |
| `tftp-wrq-server.py` | standalone WRQ |

Top-level: `rebuild-ramdisk.sh`, `rebuild-hdd-ramdisk.sh`.

## Services on helper

- `tftpd-hpa` UDP 69 → `/srv/tftp`
- SPI receiver TCP 45151
- HTTP TCP 45152 directory `/root/ds115j`
- SSH TCP 22

## HANDOFF artifact copies

Copied (not merely linked) into `/root/ds115j/HANDOFF/artifacts/`:

- `spi/` entire dump dir
- `tftp/` current + previous uImages, both ramdisks, dtb, ko
- `ds115j.dts` / `ds115j.dtb` / `ds115j-poweroff-i2c.dtb`
- `qnap-poweroff-ds115j.ko` + `qnap-poweroff-module/` source/build

Not copied (too large / not required): `linux/`, `rootfs/`, `rootfs-trixie-armhf.tar.gz`, kernel `.deb`. They remain at the paths above.
