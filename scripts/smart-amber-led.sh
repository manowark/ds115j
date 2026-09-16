#!/bin/sh
set -eu

PATH=/usr/sbin:/usr/bin:/sbin:/bin
LED_DIR=/sys/class/leds/synology:amber:disk
DEFAULT_DEVICE=/dev/sda
TAG=smart-amber-led

log_message() {
    logger -t "$TAG" -- "$*" || :
}

require_led() {
    if [ ! -w "$LED_DIR/trigger" ] || [ ! -w "$LED_DIR/brightness" ]; then
        log_message "amber LED sysfs path is unavailable: $LED_DIR"
        return 1
    fi
}

set_led() {
    value=$1
    reason=$2

    require_led
    printf '%s\n' none >"$LED_DIR/trigger"
    current=$(tr -d '\n' <"$LED_DIR/brightness")

    if [ "$current" != "$value" ]; then
        printf '%s\n' "$value" >"$LED_DIR/brightness"
        log_message "amber=$value changed reason=$reason"
    else
        log_message "amber=$value unchanged reason=$reason"
    fi
}

check_health() {
    device=${SMARTD_DEVICE:-$DEFAULT_DEVICE}

    set +e
    output=$(LC_ALL=C smartctl -H -A "$device" 2>&1)
    smartctl_rc=$?
    set -e

    # smartctl bits 0-2 mean that the check itself was unreliable. Preserve
    # the current LED state rather than falsely clearing a latched warning.
    if [ $((smartctl_rc & 7)) -ne 0 ]; then
        log_message "SMART check unavailable device=$device rc=$smartctl_rc; LED unchanged"
        return 1
    fi

    result=$(printf '%s\n' "$output" | awk '
        BEGIN { health_seen = 0; failed = 0 }
        /SMART overall-health self-assessment test result:/ {
            health_seen = 1
            if ($NF != "PASSED") failed = 1
        }
        $1 ~ /^[0-9]+$/ {
            if ($9 == "FAILING_NOW") failed = 1
            if (($1 == 197 || $1 == 198) && ($10 + 0) > 0) failed = 1
        }
        END {
            if (!health_seen) print "unknown"
            else if (failed) print "failed"
            else print "ok"
        }
    ')

    # smartctl bit 3 is failed overall health; bit 4 is a current prefailure
    # attribute at or below threshold.
    if [ $((smartctl_rc & 24)) -ne 0 ]; then
        result=failed
    fi

    case "$result" in
        failed)
            set_led 1 "SMART check failed for $device"
            ;;
        ok)
            set_led 0 "SMART check passed for $device"
            ;;
        *)
            log_message "SMART output unrecognized device=$device rc=$smartctl_rc; LED unchanged"
            return 1
            ;;
    esac
}

handle_smartd_event() {
    failtype=${SMARTD_FAILTYPE:-Unknown}
    device=${SMARTD_DEVICE:-$DEFAULT_DEVICE}

    case "$failtype" in
        Health|Usage|CurrentPendingSector|OfflineUncorrectableSector)
            set_led 1 "smartd $failtype on $device"
            ;;
        EmailTest)
            log_message "smartd hook test received for $device; LED unchanged"
            ;;
        *)
            log_message "smartd event ignored failtype=$failtype device=$device; LED unchanged"
            ;;
    esac
}

case "${1:-smartd}" in
    fail)
        set_led 1 "manual failure test"
        printf '%s\n' "amber=on"
        ;;
    ok)
        set_led 0 "manual recovery test"
        printf '%s\n' "amber=off"
        ;;
    check)
        check_health
        ;;
    status)
        printf 'trigger='
        tr '\n' ' ' <"$LED_DIR/trigger"
        printf '\nbrightness='
        tr -d '\n' <"$LED_DIR/brightness"
        printf '\n'
        ;;
    smartd)
        handle_smartd_event
        ;;
    *)
        printf 'Usage: %s {fail|ok|check|status}\n' "$0" >&2
        exit 2
        ;;
esac
