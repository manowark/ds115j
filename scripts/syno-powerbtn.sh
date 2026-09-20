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

if ! exec 3<"$TTY"; then
  echo "syno-powerbtn: cannot open $TTY for reading" >&2
  exit 4
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