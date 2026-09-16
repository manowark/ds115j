#!/bin/sh
# DS115j boot-phase MCU indicator driver.
#   begin : boot in progress   -> power LED BLINK + status LED ORANGE steady (blue blinks)
#   ready : system ready       -> power LED steady + status LED GREEN steady
#                                + one short beep
set -u

MCU=/usr/local/sbin/syno-mcu.sh

# devtmpfs should already provide /dev/ttyS1 at our start; wait briefly.
i=0
while [ ! -e /dev/ttyS1 ] && [ $i -lt 25 ]; do
  sleep 0.2
  i=$((i+1))
done

case "${1:-}" in
  begin)
    "$MCU" power blink         || exit 1
    "$MCU" status orange       || exit 1
    ;;
  ready)
    # Hard gate: beep only when the system is truly usable.
    # Wait until a network route exists, /srv/data is mounted, and zram is up.
    ready=0
    i=0
    while [ $i -lt 120 ]; do
      route_ok=0; data_ok=0; zram_ok=0
      [ -n "$(ip -o route 2>/dev/null)" ] && route_ok=1
      mountpoint -q /srv/data 2>/dev/null && data_ok=1
      grep -q 'zram0' /proc/swaps && zram_ok=1
      [ $route_ok -eq 1 ] && [ $data_ok -eq 1 ] && [ $zram_ok -eq 1 ] && { ready=1; break; }
      sleep 1
      i=$((i+1))
    done
    [ $ready -eq 1 ] || { echo "syno-mcu-boot: not ready after 120s" >&2; exit 1; }
    "$MCU" power on     || exit 1
    "$MCU" status green || exit 1
    "$MCU" beep short   || exit 1
    ;;
  *)
    echo "usage: syno-mcu-boot.sh begin|ready" >&2
    exit 2
    ;;
esac