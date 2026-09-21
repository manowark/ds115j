#!/bin/sh
# rtc-power-schedule.sh — schedule power-on at a date/time using the SoC RTC
# alarm (DSM's "auto power on" / Power Schedule equivalent, DS115j
# support_auto_poweron=yes). Uses /sys/class/rtc/rtc0/wakealarm.
#
# USAGE:
#   rtc-power-schedule.sh +MINUTES      e.g. +5   (power on 5 min from now)
#   rtc-power-schedule.sh @EPOCH        e.g. @1700000000
#   rtc-power-schedule.sh clear         remove any armed alarm
#   rtc-power-schedule.sh status        show current alarm
#
# IMPORTANT (2026-09-21): NOT yet verified live. It is unknown whether the
# RTC alarm line actually wakes the DS115j from a *software power-off*
# (qnap_poweroff_ds115j cuts the PSU; the PIC then owns power-on). Some units
# only wake from alarm when the PSU stays alive (hard power button on) or via
# the PIC's own RTC. Do the live test at the box BEFORE relying on it:
#   echo 0 > /sys/class/rtc/rtc0/wakealarm   # disarm
#   sh rtc-power-schedule.sh +2              # arm
#   poweroff                                 # then wait 2 min
# If the box comes back on its own -> works; otherwise it is equivalent to a
# soft off until the button is pressed.
set -u

RTC=/sys/class/rtc/rtc0
WAKE=$RTC/wakealarm

now_epoch() { date +%s; }

show_status() {
    local cur
    cur=$(cat "$WAKE" 2>/dev/null)
    if [ -z "$cur" ]; then
        echo "RTC alarm: none armed"
    else
        echo "RTC alarm: armed at epoch $cur = $(date -d @"$cur" '+%F %T %Z' 2>/dev/null || date -r "$cur" '+%F %T %Z')"
    fi
}

case "${1:-status}" in
    clear)
        echo 0 > "$WAKE" 2>/dev/null || { echo "failed to clear alarm" >&2; exit 1; }
        echo "alarm cleared"
        ;;
    status)
        show_status
        ;;
    +*)
        mins=${1#+}
        target=$(( $(now_epoch) + mins * 60 ))
        echo "$target" > "$WAKE" 2>/dev/null || { echo "failed to arm alarm (RTC alarm unsupported?)" >&2; exit 1; }
        echo "armed: power-on scheduled at $(date -d @"$target" '+%F %T %Z' 2>/dev/null || date -r "$target" '+%F %T %Z')"
        ;;
    @*)
        target=${1#@}
        echo "$target" > "$WAKE" 2>/dev/null || { echo "failed to arm alarm" >&2; exit 1; }
        echo "armed: power-on scheduled at $(date -d @"$target" '+%F %T %Z' 2>/dev/null || date -r "$target" '+%F %T %Z')"
        ;;
    *)
        echo "usage: $0 {+MINUTES | @EPOCH | clear | status}" >&2
        exit 2
        ;;
esac