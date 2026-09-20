# DS115j vendor firmware SPI forensics (2026-09-21)

Source: `ds115j-spi-8m-20260915-124830.bin` (8 MiB dump, sha256
cfbdc0dd57e3949957dbab23eb6befe84112fc36ed3b8a4e142c9ad78239dfc4).

Layout identified from the vendor boot log (`bootm 0xf40c0000 0xf4390000`):
- `0x0c0000` uImage kernel zImage, comp=none, payload contains an **LZMA** stream
  (Linux 3.2.101 armv7l, decompressed via `lzma -d` from `\x5d` offset).
- `0x390000` uImage ramdisk (type Multi/0x3), payload is an **LZMA-alone** stream
  of exactly 24 MiB — an **ext2 image** (block size 1024, blockmap, 128 B inodes)
  = the DSM rd rootfs.

Tools: `ext2read.py` — minimal ext2 reader used to extract the rd rootfs.

Key findings used by [docs/power-button.md](../../docs/power-button.md):
- `usr/lib/modules/synobios.ko` (synobios for Armada) is the only platform module.
- `mv_level_button` (GPIO-IRQ "level button", request_threaded_irq) is **dead code
  on DS115j** (zero relocations/pointer references) — buttons are NOT GPIO here.
- `syno_ttyS_read` / `save_char_from_uart` / `save_current_data_from_uart` /
  `current_tty_buf` (hex `%.2x` format) — the MCU channel is **UART1 (ttyS1)**,
  synchronous/polled by DSM userspace via `synobios_ioctl`.
- Conclusion: the front power button is wired to the PIC16LF1828; DSM peers with
  the PIC over /dev/ttyS1 at 9600 8N1. Under Debian the passive daemon
  `syno-powerbtn` (observe-first) listens on ttyS1 read-only.

Artifacts:
- `synobios-strings.txt` — full `strings` dump of synobios.ko
- `rootfs-filelist.txt` — every file extracted from the rd ext2 image
- `ext2read.py` — the extraction script (rerun `python3 ext2read.py` to rebuild)
