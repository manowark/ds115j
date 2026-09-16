# HANDOFF (historical bring-up notes)

**Human start:** [`../docs/install-uart.md`](../docs/install-uart.md) and [`../README.md`](../README.md).

These files preserve the 2026-09-15/16 bring-up record. References to the
former Raspberry Pi helper, `/root/ds115j`, and `/srv/tftp` describe history,
not prerequisites or current sources of artifacts.

For all installation and recovery operations use this clone:

- rootfs: `../rootfs/` + `../scripts/reconstruct-rootfs.sh`
- laptop TFTP: `../scripts/serve-tftp.sh`
- boot/DTS/SPI/module artifacts: the corresponding top-level directories
- current access instructions: `../docs/access.md`

`project-context/` (Cursor store dump) and extra historical uImages were **omitted** from git.

Do not follow helper-era copy/fetch commands in the historical notes. Start
with [`../docs/install-uart.md`](../docs/install-uart.md).
