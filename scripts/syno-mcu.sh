#!/bin/bash
# syno-mcu.sh — DS115j PIC16LF1828 (UART1 @ 9600 8N1) status-LED / power-LED control.
# Verified live 2026-09-16 on this unit (owner-confirmed states).
#
# Command map (single ASCII chars, 9600 8N1, no flow control):
#   power:  '4' steady   '5' blink   '6' off        (blue button LED)
#   status: '7' off  '8' green steady  '9' green blink
#           ':' orange steady  ';' orange blink     (front status LED)
#   beep:   '2' short  '3' long   (verified audible on this unit 2026-09-16)
#   reset:  'C' hard reset        power-off: '1'    -- handled by kernel
#           synology,power-off module at shutdown; NEVER send here.
#   'A'/'B' = D8 motherboard LED (not present on DS115j).
#
# Each command opens the port transiently and closes it, so nothing holds
# UART1 at power-off (the kernel module takes the port then, race-free).
set -euo pipefail

TTY=/dev/ttyS1

usage() {
  cat <<'USAGE'
usage: syno-mcu.sh power on|blink|off
                 status off|green|green-blink|orange|orange-blink
                 healthy            # blue steady + status green steady
                 alarm              # status orange blink + 3 long beeps
                 beep short|long    # audible on DS115j (verified)
                 ping               # no-op: verify script + tty availability
USAGE
  exit 1
}

[ $# -ge 1 ] || usage
STAGE=$1

[ -e "$TTY" ] || { echo "syno-mcu: $TTY missing" >&2; exit 2; }

stty -F "$TTY" 9600 raw -echo -onlcr -icrnl -ixon -ixoff cs8 -cstopb \
     cread clocal < /dev/null 2>/dev/null || true

send() { # send <octal> <label>
  local oct=$1 label=$2
  exec 3<>"$TTY"
  printf "\\$oct" >&3 || exit 3
  exec 3>&-
  echo "syno-mcu: $label (byte 0x$(printf '%X' $((8#$oct))))"
}

case "$STAGE" in
  power)     [ $# -eq 2 ] || usage
             case "$2" in
               on)    send 064 "power LED steady" ;;
               blink) send 065 "power LED blink" ;;
               off)   send 066 "power LED off" ;;
               *) usage ;;
             esac ;;
  status)    [ $# -eq 2 ] || usage
             case "$2" in
               off)            send 067 "status LED off" ;;
               green)          send 070 "status LED green steady" ;;
               green-blink)    send 071 "status LED green blink" ;;
               orange)         send 072 "status LED orange steady" ;;
               orange-blink)   send 073 "status LED orange blink" ;;
               *) usage ;;
             esac ;;
  healthy)   send 064 "power LED steady"; sleep 0.1; send 070 "status LED green steady" ;;
  alarm)     send 073 "status LED orange blink"
             sleep 0.5
             send 063 "long beep 1/3"; sleep 1
             send 063 "long beep 2/3"; sleep 1
             send 063 "long beep 3/3" ;;
  beep)      [ $# -eq 2 ] || usage
             case "$2" in
               short) send 062 "short beep" ;;
               long)  send 063 "long beep" ;;
               *) usage ;;
             esac ;;
  ping)      echo "syno-mcu: OK — $TTY present, script works" ;;
  *) usage ;;
esac