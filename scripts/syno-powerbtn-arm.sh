#!/bin/sh
# syno-powerbtn-arm.sh — re-send the DSM rc boot bytes so the PIC reports the
# power button (the "arming" handshake, H1 confirmed live 2026-09-21).
#
# DSM's /etc/rc does exactly this (SupportLedBehaviorV2 branch):
#   /bin/sh -c "echo 4 > /dev/ttyS1"    # 0x34 0x0A
#   /bin/sh -c "echo 9 > /dev/ttyS1"    # 0x39 0x0A
# Bare bytes (syno-mcu-boot) are NOT sufficient: the LED executes them, but the
# PIC starts pushing 0x30 (power button) only after the newline-terminated writes.
#
# Idempotent and safe: these are LED-init bytes DSM sends at every boot. A live
# press before vs after this call was the definitive test (0 bytes -> byte 0x30).
set -u

TTY=/dev/ttyS1

# Keep a window open so stty applies before each echo (matches rc's sh -c).
if ! stty -F "$TTY" 9600 raw -echo -onlcr -icrnl -ixon -ixoff cs8 -cstopb \
     cread clocal < /dev/null; then
  echo "syno-powerbtn-arm: stty on $TTY failed" >&2
  exit 1
fi

echo 4 > "$TTY"   # 0x34 0x0A
sleep 1
echo 9 > "$TTY"   # 0x39 0x0A
echo "syno-powerbtn-arm: rc boot bytes sent (0x34 0x0A, 0x39 0x0A) — PIC armed"
exit 0