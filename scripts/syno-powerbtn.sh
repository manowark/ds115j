#!/bin/bash
# syno-powerbtn.sh — DS115j front power-button daemon (PIC16LF1828 on UART1).
#
# READ-ONLY listener on /dev/ttyS1: opens the port, never writes a single byte
# (landmines: no '1', no 'C', no writes at all).  It logs every byte the MCU
# sends, and — only when TRIGGER_BYTES is configured — powers the box off on a
# matching byte.
#
# Default is OBSERVE MODE (TRIGGER_BYTES=""): log everything, never power off.
# To arm, set the hex byte(s) captured during a real button press in
# /etc/syno-powerbtn.conf (per DSM binary: power-button byte = 0x30, TRIGGER_BYTES="30")
# and restart the service.
set -u

TTY=/dev/ttyS1
CONF=/etc/syno-powerbtn.conf

BAUD=9600
SETTLE_SEC=60      # ignore triggers for N seconds after start (boot-time MCU chatter)
DEBOUNCE_SEC=30    # minimum seconds between two poweroff triggers
TRIGGER_BYTES=""   # empty = observe mode; otherwise space-separated hex bytes, e.g. "45"
# OPEN_RW=1 holds the port O_RDWR|O_NOCTTY (scemd's read-write mode; bash `<>` does
# not set O_NONBLOCK, and we deliberately do NOT want it: our read loop is a blocking
# `dd`, unlike scemd's select()+O_NONBLOCK). O_RDWR vs O_RDONLY is the variable under
# test — whether modem-line (RTS/DTR) state differs for the PIC. Default 0 = O_RDONLY.
# Still never writes a byte. Live evidence: press @07:19 UTC gave 0 bytes under
# O_RDONLY; scemd (which receives button events in DSM) never opens the port read-only.
OPEN_RW=0

[ -r "$CONF" ] && . "$CONF"

[ -e "$TTY" ] || { echo "syno-powerbtn: $TTY missing" >&2; exit 2; }

cleanup() {
  echo "syno-powerbtn: stopping"
  exit 0
}
trap cleanup TERM INT

if ! stty -F "$TTY" "$BAUD" raw -echo -onlcr -icrnl -ixon -ixoff cs8 -cstopb \
     cread clocal < /dev/null; then
  echo "syno-powerbtn: stty on $TTY failed" >&2
  exit 3
fi

if [ "$OPEN_RW" = "1" ]; then
  # Match scemd's open mode: O_RDWR (scemd uses 0x902 = O_RDWR|O_NOCTTY|O_NONBLOCK,
  # but our read loop is blocking, so no O_NONBLOCK here).
  if ! exec 3<>"$TTY"; then
    echo "syno-powerbtn: cannot open $TTY O_RDWR (scemd-style) for reading" >&2
    exit 4
  fi
  echo "[$(date '+%F %T')] port opened O_RDWR (scemd-style)"
else
  if ! exec 3<"$TTY"; then
    echo "syno-powerbtn: cannot open $TTY for reading" >&2
    exit 4
  fi
fi

START=$(date +%s)
LAST_TRIGGER=0
SESSION=""                 # consecutive bytes since the last >1s gap (hex, space separated)
SESSION_TS=$START

log() { echo "[$(date '+%F %T')] $*"; }

if [ -n "$TRIGGER_BYTES" ]; then
  log "listening on $TTY @${BAUD} 8N1 — ARMED, trigger byte(s): $TRIGGER_BYTES"
else
  log "listening on $TTY @${BAUD} 8N1 — OBSERVE MODE (logging only, never powers off)"
fi

while true; do
  # Read exactly one raw byte (blocks until the PIC transmits). No writes involved.
  hex=$(dd bs=1 count=1 <&3 2>/dev/null | od -A n -t x1 | tr -d ' \n')
  [ -n "$hex" ] || continue
  now=$(date +%s)

  # Sequence logging: group bytes that arrive within 1s of each other.
  if [ $((now - SESSION_TS)) -ge 1 ]; then
    if [ -n "$SESSION" ]; then
      log "MCU sequence:${SESSION}"
    fi
    SESSION=""
  fi
  SESSION_TS=$now
  SESSION="$SESSION $hex"

  log "byte 0x$hex"

  # Armed trigger, only after the settle window.
  if [ -n "$TRIGGER_BYTES" ] && [ $((now - START)) -ge "$SETTLE_SEC" ]; then
    for t in $TRIGGER_BYTES; do
      [ "$t" = "$hex" ] || continue
      if [ $((now - LAST_TRIGGER)) -ge "$DEBOUNCE_SEC" ]; then
        LAST_TRIGGER=$now
        log "POWER BUTTON detected (byte 0x$hex) — poweroff in 2s"
        sleep 2
        systemctl poweroff
      else
        log "trigger 0x$hex suppressed (debounce ${DEBOUNCE_SEC}s)"
      fi
      break
    done
  fi
done